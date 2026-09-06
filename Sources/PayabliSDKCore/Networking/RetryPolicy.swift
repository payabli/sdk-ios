import Foundation

/// How a retried operation waits, how long it may take in total, and which failures it retries at all.
///
/// `package`, so the SDK's own modules can name it and an app embedding the SDK cannot. The mechanism it
/// configures is not part of the integration surface, and publishing these knobs would ask an integrator
/// to reason about attempt counts, a budget and a jitter shape to reach behaviour the SDK owns.
///
/// Two bounds exist and they are not the same control. The bound on one HTTP call belongs to the
/// transport, which is where `URLSessionConfiguration`'s timeouts are set. `totalTimeout` here is the
/// second one, covering every attempt and every wait between them. This layer imposes no per-attempt
/// deadline of its own: a deadline here holds an opaque operation, so one that expired mid-refresh would
/// cancel the refresh and the next attempt would present the credential the server just rejected.
///
/// A 401 is not retryable and must not become so. Recovering from one belongs to `AuthenticatedTransport`,
/// which sits below this layer; treating `.tokenExpired` as transient here would loop refresh-and-replay
/// cycles around a credential that is not going to be accepted.
package struct RetryPolicy: Sendable {
    /// Total attempts, not retries. `1` disables retrying without disabling the caller.
    package let maxAttempts: Int
    package let baseDelay: TimeInterval
    package let maxDelay: TimeInterval
    package let multiplier: Double
    package let maxJitter: TimeInterval

    /// One deadline covering every attempt and every wait between them. `nil` installs no deadline at
    /// all, which is not the same as a very large one.
    ///
    /// An attempt is bounded by cancelling it, so the deadline is as tight as the operation is
    /// cancellable. It is honoured exactly for transport work and late for anything that ignores
    /// cancellation.
    package let totalTimeout: TimeInterval?

    /// The longest server-supplied wait worth honouring. A `Retry-After` above this ends the retry rather
    /// than being shortened, because shortening it would ignore the limit the server just stated.
    package let maxRetryAfter: TimeInterval

    package let jitter: Jitter

    /// Whether a failure is worth another attempt. Takes the whole error rather than its code, so a
    /// caller can discriminate on a subtype's fields without this signature changing.
    package let isRetryable: @Sendable (any PayabliError) -> Bool

    package static let defaultMaxAttempts = 3
    package static let defaultBaseDelay: TimeInterval = 1
    package static let defaultMaxDelay: TimeInterval = 8
    package static let defaultMultiplier = 2.0
    package static let defaultMaxJitter: TimeInterval = 0.5
    package static let defaultMaxRetryAfter: TimeInterval = 30

    /// The three transient conditions, and nothing else. A code absent from this set is not retried, so a
    /// code added later is un-retryable until someone decides otherwise.
    package static let retryableCodes: Set<PayabliErrorCode> = [
        .networkError,
        .serverError,
        .rateLimited
    ]

    package static let retryableByCode: @Sendable (any PayabliError) -> Bool = { error in
        retryableCodes.contains(error.code)
    }

    package static let `default` = RetryPolicy()

    /// Every timing input is checked. A negative delay reaches the sleep and masks the failure it was
    /// retrying, and a multiplier below one shrinks the wait on each attempt instead of growing it.
    package init(
        maxAttempts: Int = defaultMaxAttempts,
        baseDelay: TimeInterval = defaultBaseDelay,
        maxDelay: TimeInterval = defaultMaxDelay,
        multiplier: Double = defaultMultiplier,
        maxJitter: TimeInterval = defaultMaxJitter,
        totalTimeout: TimeInterval? = nil,
        maxRetryAfter: TimeInterval = defaultMaxRetryAfter,
        jitter: Jitter = .random,
        isRetryable: @escaping @Sendable (any PayabliError) -> Bool = RetryPolicy.retryableByCode
    ) {
        if let problem = Self.rejection(
            maxAttempts: maxAttempts,
            baseDelay: baseDelay,
            maxDelay: maxDelay,
            multiplier: multiplier,
            maxJitter: maxJitter,
            totalTimeout: totalTimeout,
            maxRetryAfter: maxRetryAfter
        ) {
            preconditionFailure("RetryPolicy: \(problem)")
        }

        self.maxAttempts = maxAttempts
        self.baseDelay = baseDelay
        self.maxDelay = maxDelay
        self.multiplier = multiplier
        self.maxJitter = maxJitter
        self.totalTimeout = totalTimeout
        self.maxRetryAfter = maxRetryAfter
        self.jitter = jitter
        self.isRetryable = isRetryable
    }

    /// Why these values cannot be a policy, or `nil` if they can.
    ///
    /// Separate from the initializer so the rules can be read back. Only SDK code constructs a policy, so
    /// a bad combination is a programmer error and traps rather than throwing; a trap cannot be caught,
    /// and rules nothing can exercise stop matching the ones the initializer applies.
    package static func rejection(
        maxAttempts: Int,
        baseDelay: TimeInterval,
        maxDelay: TimeInterval,
        multiplier: Double,
        maxJitter: TimeInterval,
        totalTimeout: TimeInterval?,
        maxRetryAfter: TimeInterval
    ) -> String? {
        // A table rather than a ladder: every duration needs both a range check and a finiteness one,
        // because infinity satisfies `>= 0` and `maxDelay >= baseDelay` and would otherwise reach the
        // clock as an unbounded wait. A NaN fails the range check first, since every comparison to one
        // is false.
        let rules: [(holds: Bool, complaint: String)] = [
            (maxAttempts >= 1, "requires at least 1 attempt"),
            (baseDelay >= 0, "requires a non-negative base delay"),
            (baseDelay.isFinite, "requires a finite base delay"),
            (maxDelay >= baseDelay, "requires a max delay at or above the base delay"),
            (maxDelay.isFinite, "requires a finite max delay"),
            (multiplier >= 1, "requires a multiplier of at least 1"),
            (multiplier.isFinite, "requires a finite multiplier"),
            (maxJitter >= 0, "requires a non-negative jitter bound"),
            (maxJitter.isFinite, "requires a finite jitter bound"),
            (totalTimeout.map { $0 > 0 } ?? true, "requires a positive total timeout"),
            (totalTimeout.map(\.isFinite) ?? true, "requires a finite total timeout"),
            (maxRetryAfter >= 0, "requires a non-negative retry-after ceiling"),
            (maxRetryAfter.isFinite, "requires a finite retry-after ceiling")
        ]
        return rules.first { !$0.holds }?.complaint
    }

    /// The wait before `attempt`, 1-indexed. Attempt 1 does not wait.
    ///
    /// Jitter is added after the cap, so the longest possible wait is `maxDelay + maxJitter`.
    package func delay(forAttempt attempt: Int) -> TimeInterval {
        guard attempt > 1 else { return 0 }
        let exponent = Double(attempt - 2)
        let backoff = min(baseDelay * pow(multiplier, exponent), maxDelay)
        return backoff + jitter.value(upTo: maxJitter)
    }

    /// How much of the jitter bound a given wait takes.
    package struct Jitter: Sendable {
        private let compute: @Sendable (TimeInterval) -> TimeInterval

        package init(_ compute: @escaping @Sendable (TimeInterval) -> TimeInterval) {
            self.compute = compute
        }

        package func value(upTo bound: TimeInterval) -> TimeInterval {
            compute(bound)
        }

        /// Uniform across the whole bound, which is what keeps a fleet of clients from retrying together.
        package static let random = Jitter { bound in
            bound <= 0 ? 0 : TimeInterval.random(in: 0 ... bound)
        }

        /// None, for a test asserting an exact schedule.
        package static let none = Jitter { _ in 0 }
    }
}

import Foundation

/// Runs an operation until it succeeds, the policy stops retrying it, or the budget runs out.
///
/// Applied per call site and never to every request: no write may be retried outside whatever makes a
/// duplicate of it harmless, so which routes retry is a decision per route rather than a property of the
/// transport.
///
/// The operation is expected to raise a non-2xx rather than return it. Classification is the policy's:
/// this type never inspects a status.
package enum Retry {
    /// Runs `operation`, retrying while `policy` says the failure is worth another attempt.
    ///
    /// Only a `PayabliError` is considered. Anything else propagates on the first throw, because a
    /// failure this layer cannot classify is not one it may repeat.
    package static func run<T: Sendable>(
        policy: RetryPolicy = .default,
        logger: PayabliLogger,
        clock: any RetryClock = SystemRetryClock(),
        _ operation: @escaping @Sendable (_ attempt: Int) async throws -> T
    ) async throws -> T {
        let startedAt = clock.elapsed()
        var attempt = 1

        while true {
            let remaining = remainingBudget(policy, clock: clock, startedAt: startedAt)
            if let remaining, remaining <= 0 {
                try Task.checkCancellation()
                throw budgetExhausted(logger: logger, phase: "before-attempt")
            }

            // Copied before the closure captures it: the loop reassigns `attempt`, and a `var` crossing
            // into concurrently-executing code is an error under the Swift 6 language mode.
            let thisAttempt = attempt
            let outcome: T?
            do {
                if let remaining {
                    outcome = try await withBudget(remaining, clock: clock) {
                        try await operation(thisAttempt)
                    }
                } else {
                    outcome = try await operation(thisAttempt)
                }
            } catch let failure as any PayabliError {
                // A layer below may have classified a cancelled call as a transient failure, which is
                // retryable, so the caller who cancelled would have the request sent again. Asked before
                // the failure is classified, so no policy can make cancellation worth repeating.
                try Task.checkCancellation()
                attempt = try await nextAttempt(
                    after: failure,
                    attempt: attempt,
                    policy: policy,
                    logger: logger,
                    clock: clock,
                    startedAt: startedAt
                )
                continue
            }

            // Outside the catch, so an expired budget is never offered to the retry decision. It is not a
            // failure of the operation and repeating it would only spend the time again.
            guard let outcome else {
                try Task.checkCancellation()
                throw budgetExhausted(logger: logger, phase: "in-attempt")
            }
            return outcome
        }
    }

    /// The attempt number to run next, or a throw if there is not going to be one.
    private static func nextAttempt(
        after failure: any PayabliError,
        attempt: Int,
        policy: RetryPolicy,
        logger: PayabliLogger,
        clock: any RetryClock,
        startedAt: TimeInterval
    ) async throws -> Int {
        guard attempt < policy.maxAttempts, policy.isRetryable(failure) else { throw failure }

        let serverHint = (failure as? any PayabliRetryAfter)?.retryAfter
        if let serverHint, serverHint > policy.maxRetryAfter {
            // Shortening it would ignore the limit the server just stated, and waiting it out is not
            // something to do on a caller's behalf. Stop, and report what the server actually said.
            logger.warning("retry-after exceeds the ceiling; not retrying (\(failure.code.rawValue))")
            throw failure
        }

        let wait = serverHint ?? policy.delay(forAttempt: attempt + 1)
        if let remaining = remainingBudget(policy, clock: clock, startedAt: startedAt), wait >= remaining {
            // Sleeping past the budget only delays the same failure.
            logger.warning("total budget exhausted; not retrying (\(failure.code.rawValue))")
            throw failure
        }

        logger.debug("attempt \(attempt) failed with \(failure.code.rawValue); retrying in \(wait)s")
        try await clock.sleep(for: wait)
        return attempt + 1
    }

    private static func remainingBudget(
        _ policy: RetryPolicy,
        clock: any RetryClock,
        startedAt: TimeInterval
    ) -> TimeInterval? {
        guard let total = policy.totalTimeout else { return nil }
        return total - (clock.elapsed() - startedAt)
    }

    private static func budgetExhausted(logger: PayabliLogger, phase: String) -> PayabliGenericError {
        logger.warning("operation exceeded its total timeout (\(phase))")
        return PayabliGenericError(
            code: .networkError,
            reason: "Operation exceeded its total timeout"
        )
    }

    /// Runs `operation` under `seconds`, answering `nil` if the bound is reached first.
    ///
    /// The optional is what separates an expiry from the operation legitimately answering, which a bare
    /// throw could not.
    ///
    /// **The bound is only as tight as `operation` is cancellable.** A task group cannot leave its scope
    /// until every child has finished, so reaching the deadline cancels the operation and then waits for
    /// it to notice. An operation that ignores cancellation runs to completion and the budget expires
    /// late rather than on time; it never returns while that work is still in flight, which is what would
    /// make a write unsafe. Every caller is transport work over `URLSession`, which ends promptly on
    /// cancellation. An operation that blocks without checking does not belong under a budget.
    private static func withBudget<T: Sendable>(
        _ seconds: TimeInterval,
        clock: any RetryClock,
        _ operation: @escaping @Sendable () async throws -> T
    ) async throws -> T? {
        try await withThrowingTaskGroup(of: T?.self) { group in
            group.addTask { try await operation() }
            group.addTask {
                try await clock.sleep(for: seconds)
                return nil
            }
            defer { group.cancelAll() }
            // The first to finish decides; `nil` can only have come from the timer.
            return try await group.next() ?? nil
        }
    }
}

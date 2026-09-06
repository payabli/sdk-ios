import Foundation
@testable import PayabliSDKCore

/// A clock a test drives, so a schedule is asserted rather than waited out.
///
/// `sleep` advances the clock and returns; nothing suspends on a real timer. That is what lets a case
/// assert the exact elapsed total, which a policy with its delays set to zero cannot: zeroed delays make
/// every schedule look identical and pass whatever the arithmetic did.
final class FakeRetryClock: RetryClock, @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: TimeInterval = 0
    private var slept: [TimeInterval] = []

    func elapsed() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return seconds
    }

    /// Advances the clock by `seconds` after a short real pause.
    ///
    /// `Retry` races the attempt against this sleep to bound it, so a sleep that returned at once would
    /// report every attempt as an expiry, the ones that failed on their own included. The pause settles
    /// that race the way a real deadline does: an operation that completes without blocking always wins
    /// it, and only one that is genuinely blocked loses. It is ordering and not measurement — what a case
    /// asserts is the virtual total, which moves by `seconds` and not by the pause.
    func sleep(for seconds: TimeInterval) async throws {
        try await Task.sleep(nanoseconds: 30_000_000)
        lock.lock()
        self.seconds += seconds
        slept.append(seconds)
        lock.unlock()
    }

    /// Every wait asked for, in order.
    var waits: [TimeInterval] {
        lock.lock()
        defer { lock.unlock() }
        return slept
    }

    /// Moves the clock without a sleep, for a test standing in for work that took time.
    func advance(by interval: TimeInterval) {
        lock.lock()
        defer { lock.unlock() }
        seconds += interval
    }
}

/// A clock whose wait neither suspends nor observes cancellation.
///
/// `FakeRetryClock` waits on `Task.sleep`, which raises on a cancelled task, so a case about cancellation
/// run against it stops in the backoff and reports cancellation whatever the code under test did. This one
/// lets a retry proceed, so a guard that should have stopped it is the only thing that can.
final class ImmediateRetryClock: RetryClock, @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: TimeInterval = 0

    func elapsed() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return seconds
    }

    func sleep(for seconds: TimeInterval) async throws {
        lock.lock()
        self.seconds += seconds
        lock.unlock()
    }
}

/// Counts attempts across a retried operation.
actor AttemptCounter {
    private(set) var count = 0

    func next() -> Int {
        count += 1
        return count
    }
}

/// A `PayabliError` with a caller-chosen code, so a case can name the classification it is testing.
struct TestFailure: PayabliError {
    let code: PayabliErrorCode
    let reason: String
    let detail: String? = nil

    init(_ code: PayabliErrorCode, reason: String = "test failure") {
        self.code = code
        self.reason = reason
    }
}

/// A retryable failure carrying a server hint, which only a 429 or a 5xx can.
struct TestHintedFailure: PayabliError, PayabliRetryAfter {
    let code: PayabliErrorCode
    let retryAfter: TimeInterval?
    let reason = "test failure with a hint"
    let detail: String? = nil
}

extension RetryPolicy {
    /// A policy with jitter off, so a schedule is exact.
    static func test(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 1,
        maxDelay: TimeInterval = 8,
        multiplier: Double = 2,
        totalTimeout: TimeInterval? = nil,
        maxRetryAfter: TimeInterval = 30
    ) -> RetryPolicy {
        RetryPolicy(
            maxAttempts: maxAttempts,
            baseDelay: baseDelay,
            maxDelay: maxDelay,
            multiplier: multiplier,
            maxJitter: 0,
            totalTimeout: totalTimeout,
            maxRetryAfter: maxRetryAfter,
            jitter: .none
        )
    }
}

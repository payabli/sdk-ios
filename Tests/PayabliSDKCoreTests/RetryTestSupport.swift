import Foundation
@testable import PayabliSDKCore

/// A clock a test drives, so a schedule is asserted rather than waited out.
///
/// Nothing here suspends on a real timer, which is what lets a case assert an exact elapsed total. A
/// policy with its delays zeroed cannot: zeroed delays make every schedule look identical and pass
/// whatever the arithmetic did.
final class FakeRetryClock: RetryClock, @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: TimeInterval = 0
    private var slept: [TimeInterval] = []
    private var parked: [CheckedContinuation<Void, Never>] = []

    /// Whether a bounded attempt is allowed to reach its deadline. Off by default, so the operation wins
    /// unless a case says otherwise.
    private var deadlineIsOpen = false

    func elapsed() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return seconds
    }

    /// Advances the clock by `seconds` and returns. A backoff wait is a decision already taken, so
    /// nothing here delays it.
    func sleep(for seconds: TimeInterval) async throws {
        try Task.checkCancellation()
        lock.lock()
        self.seconds += seconds
        slept.append(seconds)
        lock.unlock()
    }

    /// Holds until a case opens the deadline, so what wins the race against an attempt is a decision
    /// rather than elapsed time. A loaded executor cannot make a deadline fire that a case did not ask
    /// for, and cannot delay one it did.
    func expire(after seconds: TimeInterval) async throws {
        lock.lock()
        let open = deadlineIsOpen
        if open {
            self.seconds += seconds
        }
        lock.unlock()

        if !open {
            await withTaskCancellationHandler {
                await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                    lock.lock()
                    // Read under the lock, and per call rather than from state on the clock: `onCancel`
                    // can run before this closure does, and a continuation stored after that would never
                    // be resumed. A flag on the clock would stay set for every later attempt.
                    if Task.isCancelled {
                        lock.unlock()
                        continuation.resume()
                        return
                    }
                    parked.append(continuation)
                    lock.unlock()
                }
            } onCancel: {
                self.releaseParked()
            }
        }
        try Task.checkCancellation()
    }

    /// Lets a bounded attempt reach its deadline, for the cases that are about the budget expiring.
    func openTheDeadline() {
        lock.lock()
        deadlineIsOpen = true
        lock.unlock()
        releaseParked()
    }

    private func releaseParked() {
        lock.lock()
        let waiting = parked
        parked = []
        lock.unlock()
        for continuation in waiting {
            continuation.resume()
        }
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

/// A clock that observes no cancellation at all.
///
/// `FakeRetryClock` raises on a cancelled task, so a case about cancellation run against it stops in the
/// backoff and reports cancellation whatever the code under test did. This one lets a retry proceed, so a
/// guard that should have stopped it is the only thing that can.
final class ImmediateRetryClock: RetryClock, @unchecked Sendable {
    private let lock = NSLock()
    private var seconds: TimeInterval = 0
    private var parked: CheckedContinuation<Void, Never>?

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

    /// Never fires. A case using this clock is about what happens without a deadline.
    func expire(after seconds: TimeInterval) async throws {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                parked = continuation
                lock.unlock()
            }
        } onCancel: {
            self.lock.lock()
            let waiting = self.parked
            self.parked = nil
            self.lock.unlock()
            waiting?.resume()
        }
    }
}

/// Runs a hook during the wait between attempts, so a case can land an event in the window between the
/// retry decision and the attempt it leads to.
///
/// That window is not otherwise reachable: the loop checks cancellation when it catches a failure, so a
/// cancellation arriving before that is seen there and never reaches the next attempt.
final class SleepHookClock: RetryClock, @unchecked Sendable {
    private let lock = NSLock()
    private var hook: (@Sendable () -> Void)?
    private var seconds: TimeInterval = 0

    func onSleep(_ hook: @escaping @Sendable () -> Void) {
        lock.lock()
        defer { lock.unlock() }
        self.hook = hook
    }

    func elapsed() -> TimeInterval {
        lock.lock()
        defer { lock.unlock() }
        return seconds
    }

    func sleep(for seconds: TimeInterval) async throws {
        lock.lock()
        self.seconds += seconds
        let fire = hook
        lock.unlock()
        fire?()
    }

    /// Never fires. A case using this clock is about the wait, not the deadline.
    func expire(after seconds: TimeInterval) async throws {
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                continuation.resume()
            }
        } onCancel: {}
        try await Task.sleep(nanoseconds: .max)
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

/// Holds a task so a hook set after its creation can cancel it.
final class TaskHolder: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelHeld: (@Sendable () -> Void)?

    func hold(_ task: Task<some Sendable, Error>) {
        lock.lock()
        defer { lock.unlock() }
        cancelHeld = { task.cancel() }
    }

    func cancel() {
        lock.lock()
        let cancelIt = cancelHeld
        lock.unlock()
        cancelIt?()
    }
}

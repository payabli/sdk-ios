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
    private var parked: [(continuation: CheckedContinuation<Void, Never>, seconds: TimeInterval)] = []

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
        await withTaskCancellationHandler {
            await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
                lock.lock()
                // Both reads happen here, under the same lock the append takes. Reading the gate first and
                // appending afterwards leaves a window: an open, or a cancel, landing between the two
                // releases a list this continuation is not in yet, and it then parks for good.
                if deadlineIsOpen {
                    self.seconds += seconds
                    lock.unlock()
                    continuation.resume()
                    return
                }
                if Task.isCancelled {
                    lock.unlock()
                    continuation.resume()
                    return
                }
                parked.append((continuation, seconds))
                lock.unlock()
            }
        } onCancel: {
            // Without advancing: a deadline the attempt beat did not elapse, and moving the clock for it
            // would spend budget on a wait that never happened.
            self.releaseParked(advancingClock: false)
        }
        try Task.checkCancellation()
    }

    /// Lets a bounded attempt reach its deadline, for the cases that are about the budget expiring.
    func openTheDeadline() {
        lock.lock()
        deadlineIsOpen = true
        lock.unlock()
        releaseParked(advancingClock: true)
    }

    /// Resumes everything parked. A deadline that fires advances the clock by the wait it was holding, so
    /// one opened after the fact lands where one opened before it would have.
    private func releaseParked(advancingClock: Bool) {
        lock.lock()
        let waiting = parked
        parked = []
        if advancingClock {
            for entry in waiting {
                seconds += entry.seconds
            }
        }
        lock.unlock()
        for entry in waiting {
            entry.continuation.resume()
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

@testable import PayabliSDKCore
import XCTest

final class RetryPolicyTests: XCTestCase {
    func testDefaultParameters() {
        let policy = RetryPolicy.default
        XCTAssertEqual(policy.maxAttempts, 3)
        XCTAssertEqual(policy.baseDelay, 1.0)
        XCTAssertEqual(policy.maxDelay, 8.0)
        XCTAssertEqual(policy.multiplier, 2.0)
        XCTAssertEqual(policy.maxJitter, 0.5)
        XCTAssertEqual(policy.maxRetryAfter, 30)
        XCTAssertNil(policy.totalTimeout, "no whole-operation deadline unless one is asked for")
    }

    func testDelayForAttempt() {
        let policy = RetryPolicy.test()
        XCTAssertEqual(policy.delay(forAttempt: 1), 0, "the first attempt does not wait")
        XCTAssertEqual(policy.delay(forAttempt: 2), 1)
        XCTAssertEqual(policy.delay(forAttempt: 3), 2)
        XCTAssertEqual(policy.delay(forAttempt: 4), 4)
    }

    func testDelayCapsAtMaxDelay() {
        let policy = RetryPolicy.test(maxDelay: 3)
        XCTAssertEqual(policy.delay(forAttempt: 9), 3)
    }

    /// Asserted against a jitter that always returns its whole bound, so the sum is exact. Bounds alone
    /// would be satisfied by an implementation that returned the capped backoff and added nothing.
    func testJitterIsAddedAfterTheCapSoTheCeilingIsTheSumOfBoth() {
        let policy = RetryPolicy(
            maxDelay: 2,
            maxJitter: 0.5,
            jitter: RetryPolicy.Jitter { $0 }
        )

        XCTAssertEqual(policy.delay(forAttempt: 9), 2.5, "the cap plus the whole bound")
        XCTAssertEqual(policy.delay(forAttempt: 2), policy.baseDelay + 0.5, "and before the cap is reached")
    }

    func testJitterNoneProducesAnExactSchedule() {
        XCTAssertEqual(RetryPolicy.Jitter.none.value(upTo: 10), 0)
    }

    func testJitterRandomStaysInsideItsBound() {
        for _ in 0 ..< 50 {
            let value = RetryPolicy.Jitter.random.value(upTo: 0.25)
            XCTAssertGreaterThanOrEqual(value, 0)
            XCTAssertLessThanOrEqual(value, 0.25)
        }
    }

    func testAZeroJitterBoundProducesNoJitter() {
        XCTAssertEqual(RetryPolicy.Jitter.random.value(upTo: 0), 0)
    }

    /// The closure is supplied, so its answer is checked the way every other timing input is. Left
    /// unclamped it defeats the initializer's validation from outside the policy.
    func testAJitterAnsweringOutsideItsBoundIsClamped() {
        XCTAssertEqual(RetryPolicy.Jitter { _ in -5 }.value(upTo: 0.5), 0, "never shortens the wait")
        XCTAssertEqual(RetryPolicy.Jitter { _ in 9 }.value(upTo: 0.5), 0.5, "never passes the bound")
        XCTAssertEqual(RetryPolicy.Jitter { _ in .infinity }.value(upTo: 0.5), 0, "never reaches the clock")
        XCTAssertEqual(RetryPolicy.Jitter { _ in .nan }.value(upTo: 0.5), 0)
    }

    // MARK: - What a policy refuses to be

    /// Read back through `rejection` rather than by constructing one: only SDK code builds a policy, so a
    /// bad combination traps, and a trap cannot be caught by a test.
    func testTheDefaultsAreValid() {
        XCTAssertNil(rejection())
    }

    func testMaxAttemptsBelowOneIsRejected() {
        XCTAssertNotNil(rejection(maxAttempts: 0))
    }

    func testOneAttemptIsAccepted() {
        XCTAssertNil(rejection(maxAttempts: 1), "retrying can be switched off without the caller being")
    }

    func testANegativeBaseDelayIsRejected() {
        XCTAssertNotNil(rejection(baseDelay: -1))
    }

    func testAMaxDelayBelowTheBaseDelayIsRejected() {
        XCTAssertNotNil(rejection(baseDelay: 5, maxDelay: 1))
    }

    func testAMultiplierBelowOneIsRejected() {
        XCTAssertNotNil(rejection(multiplier: 0.5))
    }

    func testANonFiniteMultiplierIsRejected() {
        XCTAssertNotNil(rejection(multiplier: .infinity))
        XCTAssertNotNil(rejection(multiplier: .nan))
    }

    func testANegativeJitterBoundIsRejected() {
        XCTAssertNotNil(rejection(maxJitter: -0.1))
    }

    func testANonFiniteJitterBoundIsRejected() {
        XCTAssertNotNil(rejection(maxJitter: .infinity))
    }

    /// Infinity satisfies `>= 0` and `maxDelay >= baseDelay`, so without an explicit check an unbounded
    /// wait reaches the clock as a valid policy.
    func testANonFiniteDurationIsRejectedWhicheverOneItIs() {
        XCTAssertNotNil(rejection(baseDelay: .infinity, maxDelay: .infinity), "base delay")
        XCTAssertNotNil(rejection(maxDelay: .infinity), "max delay")
        XCTAssertNotNil(rejection(totalTimeout: .infinity), "total timeout")
        XCTAssertNotNil(rejection(maxRetryAfter: .infinity), "retry-after ceiling")
        XCTAssertNotNil(rejection(baseDelay: .nan), "a NaN base delay fails every comparison")
    }

    /// Jitter is added after the cap, so the two together are the longest wait the policy can produce.
    /// Each is finite at `greatestFiniteMagnitude` and the sum of two of them is not.
    func testANonFiniteLongestWaitIsRejected() {
        XCTAssertNotNil(
            rejection(maxDelay: .greatestFiniteMagnitude, maxJitter: .greatestFiniteMagnitude)
        )
    }

    func testANonPositiveTotalTimeoutIsRejected() {
        XCTAssertNotNil(rejection(totalTimeout: 0))
        XCTAssertNotNil(rejection(totalTimeout: -1))
    }

    /// A base of zero with a growth that overflows still waits a number.
    ///
    /// `0 * .infinity` is NaN, and every comparison against one is false, so a NaN wait passes the budget
    /// checks that exist to catch a wait too long and then reaches the clock as no wait at all. Both
    /// values are ones the initializer accepts.
    func testAZeroBaseAndAGrowthThatOverflowsStillWaitANumber() {
        let policy = RetryPolicy(
            maxAttempts: 5,
            baseDelay: 0,
            maxDelay: 8,
            multiplier: 1e300,
            maxJitter: 0,
            jitter: .none
        )

        for attempt in 1 ... 5 {
            let wait = policy.delay(forAttempt: attempt)
            XCTAssertTrue(wait.isFinite, "attempt \(attempt) waits \(wait)")
            XCTAssertEqual(wait, 0, "a base of zero is a policy with no computed backoff")
        }
    }

    /// The jitter a zero base is configured with is still the wait, since jitter is added after the cap.
    func testAZeroBaseStillTakesTheJitterItWasGiven() {
        let policy = RetryPolicy(
            maxAttempts: 3,
            baseDelay: 0,
            maxDelay: 8,
            multiplier: 1e300,
            maxJitter: 0.5,
            jitter: RetryPolicy.Jitter { $0 }
        )

        XCTAssertEqual(policy.delay(forAttempt: 2), 0.5)
    }

    func testANegativeRetryAfterCeilingIsRejected() {
        XCTAssertNotNil(rejection(maxRetryAfter: -1))
    }

    private func rejection(
        maxAttempts: Int = 3,
        baseDelay: TimeInterval = 1,
        maxDelay: TimeInterval = 8,
        multiplier: Double = 2,
        maxJitter: TimeInterval = 0.5,
        totalTimeout: TimeInterval? = nil,
        maxRetryAfter: TimeInterval = 30
    ) -> String? {
        RetryPolicy.rejection(
            maxAttempts: maxAttempts,
            baseDelay: baseDelay,
            maxDelay: maxDelay,
            multiplier: multiplier,
            maxJitter: maxJitter,
            totalTimeout: totalTimeout,
            maxRetryAfter: maxRetryAfter
        )
    }
}

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

    func testJitterIsAddedAfterTheCapSoTheCeilingIsTheSumOfBoth() {
        let policy = RetryPolicy(maxDelay: 2, maxJitter: 0.5)
        for _ in 0 ..< 50 {
            let delay = policy.delay(forAttempt: 9)
            XCTAssertGreaterThanOrEqual(delay, 2)
            XCTAssertLessThanOrEqual(delay, 2.5)
        }
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

    func testANonPositiveTotalTimeoutIsRejected() {
        XCTAssertNotNil(rejection(totalTimeout: 0))
        XCTAssertNotNil(rejection(totalTimeout: -1))
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

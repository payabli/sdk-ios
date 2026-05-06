import XCTest
import PayabliSDKCore

final class RetryPolicyTests: XCTestCase {

    func testDefaultParameters() {
        let policy = RetryPolicy.default
        XCTAssertEqual(policy.maxAttempts, 3)
        XCTAssertEqual(policy.baseDelay, 1.0)
        XCTAssertEqual(policy.maxDelay, 8.0)
        XCTAssertEqual(policy.multiplier, 2.0)
        XCTAssertEqual(policy.maxJitter, 0.5)
    }

    func testMinimumValidMaxAttempts() {
        // maxAttempts == 1 is the minimum valid value; construction must not trap.
        let policy = RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0)
        XCTAssertEqual(policy.maxAttempts, 1)
    }

    func testDelayForAttempt() {
        let policy = RetryPolicy(maxAttempts: 4, baseDelay: 1, maxDelay: 8, multiplier: 2, maxJitter: 0)
        XCTAssertEqual(policy.delay(forAttempt: 1), 0)
        XCTAssertEqual(policy.delay(forAttempt: 2), 1)
        XCTAssertEqual(policy.delay(forAttempt: 3), 2)
        XCTAssertEqual(policy.delay(forAttempt: 4), 4)
    }

    func testDelayCapsAtMaxDelay() {
        let policy = RetryPolicy(maxAttempts: 10, baseDelay: 1, maxDelay: 8, multiplier: 2, maxJitter: 0)
        XCTAssertEqual(policy.delay(forAttempt: 10), 8)
    }

    func testJitterBounds() {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 1, maxDelay: 8, multiplier: 2, maxJitter: 0.5)
        for _ in 0..<20 {
            let delay = policy.delay(forAttempt: 2)
            XCTAssertTrue(delay >= 1.0 && delay <= 1.5)
        }
    }

    func testRetryableStatusCodes() {
        let policy = RetryPolicy.default
        XCTAssertTrue(policy.isRetryable(statusCode: 500))
        XCTAssertTrue(policy.isRetryable(statusCode: 502))
        XCTAssertTrue(policy.isRetryable(statusCode: 503))
        XCTAssertTrue(policy.isRetryable(statusCode: 504))
        XCTAssertTrue(policy.isRetryable(statusCode: 408))
        XCTAssertFalse(policy.isRetryable(statusCode: 400))
        XCTAssertFalse(policy.isRetryable(statusCode: 401))
        XCTAssertFalse(policy.isRetryable(statusCode: 403))
        XCTAssertFalse(policy.isRetryable(statusCode: 404))
        XCTAssertFalse(policy.isRetryable(statusCode: 200))
    }

    // MARK: - Retry.run

    func testRetryRunSucceedsOnFirstAttempt() async throws {
        var attempts = 0
        let result = try await Retry.run(policy: RetryPolicy(maxAttempts: 3, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0)) { attempt in
            attempts += 1
            return attempt
        }
        XCTAssertEqual(result, 1)
        XCTAssertEqual(attempts, 1)
    }

    func testRetryRunRetriesRetryableErrors() async throws {
        var attempts = 0
        let result = try await Retry.run(policy: RetryPolicy(maxAttempts: 3, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0)) { attempt in
            attempts += 1
            if attempt < 3 {
                throw RetryableError(NSError(domain: "test", code: 500))
            }
            return attempt
        }
        XCTAssertEqual(result, 3)
        XCTAssertEqual(attempts, 3)
    }

    func testRetryRunThrowsAfterMaxAttempts() async {
        var attempts = 0
        do {
            _ = try await Retry.run(policy: RetryPolicy(maxAttempts: 2, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0)) { _ in
                attempts += 1
                throw RetryableError(NSError(domain: "test", code: 500))
            }
            XCTFail("should have thrown")
        } catch let nsError as NSError {
            XCTAssertEqual(attempts, 2)
            XCTAssertEqual(nsError.domain, "test")
            XCTAssertEqual(nsError.code, 500)
        } catch {
            XCTFail("expected NSError but got \(type(of: error))")
        }
    }

    func testRetryRunPropagatesNonRetryableErrors() async {
        struct Fatal: Error {}
        var attempts = 0
        do {
            _ = try await Retry.run(policy: RetryPolicy.default) { _ in
                attempts += 1
                throw Fatal()
            }
            XCTFail("should have thrown")
        } catch is Fatal {
            XCTAssertEqual(attempts, 1, "Non-retryable errors must not trigger retries")
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}

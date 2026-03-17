import XCTest
@testable import PayabliTTP

final class RetryPolicyTests: XCTestCase {

    func testSucceedsOnFirstAttempt() async throws {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.01, maxDelay: 0.1)
        var callCount = 0

        let result: String = try await policy.execute {
            callCount += 1
            return "ok"
        }

        XCTAssertEqual(result, "ok")
        XCTAssertEqual(callCount, 1)
    }

    func testRetriesOnNetworkError() async throws {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.01, maxDelay: 0.1)
        var callCount = 0

        let result: String = try await policy.execute {
            callCount += 1
            if callCount < 3 {
                throw PayabliTTPError.networkError("timeout")
            }
            return "recovered"
        }

        XCTAssertEqual(result, "recovered")
        XCTAssertEqual(callCount, 3)
    }

    func testRetriesOn5xxError() async throws {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.01, maxDelay: 0.1)
        var callCount = 0

        let result: String = try await policy.execute {
            callCount += 1
            if callCount < 2 {
                throw PayabliTTPError.backendError(statusCode: 502, message: "Bad Gateway")
            }
            return "recovered"
        }

        XCTAssertEqual(result, "recovered")
        XCTAssertEqual(callCount, 2)
    }

    func testDoesNotRetryOn4xxError() async {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.01, maxDelay: 0.1)
        var callCount = 0

        do {
            let _: String = try await policy.execute {
                callCount += 1
                throw PayabliTTPError.backendError(statusCode: 401, message: "Unauthorized")
            }
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual(callCount, 1, "Should not retry 4xx errors")
        }
    }

    func testExhaustsAllAttempts() async {
        let policy = RetryPolicy(maxAttempts: 3, baseDelay: 0.01, maxDelay: 0.1)
        var callCount = 0

        do {
            let _: String = try await policy.execute {
                callCount += 1
                throw PayabliTTPError.networkError("persistent failure")
            }
            XCTFail("Should have thrown")
        } catch {
            XCTAssertEqual(callCount, 3, "Should attempt exactly maxAttempts times")
        }
    }
}

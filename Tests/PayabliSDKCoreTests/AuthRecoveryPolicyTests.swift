@_spi(PayabliInternal) @testable import PayabliSDKCore
import XCTest

final class AuthRecoveryPolicyTests: XCTestCase {
    private let policy = DefaultAuthRecoveryPolicy()

    private func response(_ status: Int) -> PayabliResponse {
        PayabliResponse(statusCode: status, headers: [:], body: Data())
    }

    func testOnlyA401IsACredentialRejection() {
        XCTAssertTrue(policy.isCredentialRejection(response(401)))
    }

    func testASuccessIsNotACredentialRejection() {
        XCTAssertFalse(policy.isCredentialRejection(response(200)))
    }

    func testTheCredentialAdjacentStatusesAreNotRejectionsThisPolicyRecovers() {
        // A 403 is a decision about what this credential may do, a 410 a session that is gone and a 402 a
        // decline. A different credential changes none of them.
        for status in [402, 403, 410] {
            XCTAssertFalse(
                policy.isCredentialRejection(response(status)),
                "\(status) must not trigger a refresh"
            )
        }
    }

    func testATransientFailureIsLeftToTheRetryPolicy() {
        for status in [429, 500, 503] {
            XCTAssertFalse(
                policy.isCredentialRejection(response(status)),
                "\(status) is the retry layer's, not this one's"
            )
        }
    }

    func testAnExhaustedRecoveryIsTokenExpired() {
        XCTAssertEqual(policy.exhausted().code, .tokenExpired)
    }

    func testAnExhaustedRecoveryCarriesNoServerText() {
        let error = policy.exhausted()
        XCTAssertEqual(error.reason, "Refresh token rejected")
        XCTAssertNil(error.detail, "a 401 body belongs to the service")
    }

    /// The invariant that keeps the two layers from fighting. Without it a settled credential failure
    /// reads as transient to the retry layer above, which then spends the whole policy on refresh cycles.
    func testTokenExpiredIsExcludedFromTheRetryableSetSoTheTwoPoliciesDoNotOverlap() {
        XCTAssertFalse(RetryPolicy.retryableCodes.contains(DefaultAuthRecoveryPolicy().exhausted().code))
    }

    /// A widened policy changes what refreshes. It must not change what the exhausted failure says, which
    /// is why `exhausted()` is not a protocol requirement.
    func testAWidenedPolicyStillReportsTheSameTerminalFailure() {
        struct Widened: AuthRecoveryPolicy {
            func isCredentialRejection(_ response: PayabliResponse) -> Bool {
                response.statusCode == 401 || response.statusCode == 419
            }
        }
        let widened = Widened()
        XCTAssertTrue(widened.isCredentialRejection(response(419)))
        XCTAssertEqual(widened.exhausted().code, .tokenExpired)
    }
}

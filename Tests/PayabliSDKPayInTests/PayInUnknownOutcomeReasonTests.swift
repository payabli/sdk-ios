import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// The reason each money route reports when the outcome is unknown.
///
/// One test per route: the routes share one sentence today, and each is pinned on its own so a
/// reason that drifts on one route fails that route's test.
@MainActor
final class PayInUnknownOutcomeReasonTests: XCTestCase {
    func testAnInterruptedCaptureNamesTheTransaction() async {
        let transport = RecordingIdempotencyTransport(
            failure: PayabliGenericError(type: .networkError, reason: "offline")
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reason-capture")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.capture(PayInFixture.request())
        })

        guard let error = failure as? PayabliPayInError, case .submissionInterrupted = error else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }

        XCTAssertEqual(
            error.reason,
            "The transaction's status is unknown. Read the transaction back to see its status."
        )
    }

    func testAnInterruptedAuthorizationNamesTheTransaction() async {
        let transport = RecordingIdempotencyTransport(
            failure: PayabliGenericError(type: .networkError, reason: "offline")
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reason-authorize")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.authorize(PayInFixture.request(cardOnly: true))
        })

        guard let error = failure as? PayabliPayInError, case .submissionInterrupted = error else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }

        XCTAssertEqual(
            error.reason,
            "The transaction's status is unknown. Read the transaction back to see its status."
        )
    }

    func testAnInterruptedCaptureOfAnAuthorizationNamesTheTransaction() async {
        let transport = RecordingIdempotencyTransport(
            failure: PayabliGenericError(type: .networkError, reason: "offline")
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reason-capture-authorized")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.captureAuthorizedTransaction(
                PayabliPayInAuthorizedRequest(
                    transId: "trans-1",
                    paymentDetails: PayabliPayInPaymentDetails(totalAmount: 10)
                )
            )
        })

        guard let error = failure as? PayabliPayInError, case .submissionInterrupted = error else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }

        XCTAssertEqual(
            error.reason,
            "The transaction's status is unknown. Read the transaction back to see its status."
        )
    }

    /// After a reversal the open question is whether it applied, so the reason names no payment and
    /// nothing taken.
    func testAnInterruptedVoidNamesTheTransaction() async {
        let transport = RecordingIdempotencyTransport(
            failure: PayabliGenericError(type: .networkError, reason: "offline")
        )
        let flow = PayInFixture.makeFlow(transport: transport, key: "reason-void")

        let failure = await PayInFixture.failure(from: {
            _ = try await flow.voidTransaction("trans-1")
        })

        guard let error = failure as? PayabliPayInError, case .submissionInterrupted = error else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }

        XCTAssertEqual(
            error.reason,
            "The transaction's status is unknown. Read the transaction back to see its status."
        )
        XCTAssertFalse(error.reason.contains("payment"), error.reason)
        XCTAssertFalse(error.reason.contains("taken"), error.reason)
    }
}

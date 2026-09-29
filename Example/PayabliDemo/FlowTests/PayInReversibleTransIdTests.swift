import PayabliSDKPayIn
import XCTest

/// Which payments the capture screen offers a reversal for.
///
/// The screen reads this rather than the raw identifier, because present is not the same as usable:
/// the SDK trims the value, refuses a blank one, and refuses `.` and `..` besides. A button offered
/// for any of those can only ever come back as invalid input, which teaches an operator that
/// reversal is unreliable rather than that the identifier was never one.
final class PayInReversibleTransIdTests: XCTestCase {
    func testAnIdentifierIsOfferedTrimmed() {
        XCTAssertEqual(outcome(withTransId: "  32-abc  ").reversibleTransId, "32-abc")
    }

    func testAnAbsentIdentifierIsNotOffered() {
        XCTAssertNil(outcome(withTransId: nil).reversibleTransId)
    }

    func testABlankIdentifierIsNotOffered() {
        XCTAssertNil(outcome(withTransId: "   ").reversibleTransId)
    }

    /// Both survive the SDK's percent encoder, which keeps the RFC 3986 unreserved set, so either
    /// would name a route rather than a transaction. The SDK refuses them before sending.
    func testAReservedPathSegmentIsNotOffered() {
        for transId in [".", "..", " . ", " .. "] {
            XCTAssertNil(
                outcome(withTransId: transId).reversibleTransId,
                "\(transId) is not a transaction"
            )
        }
    }

    private func outcome(withTransId transId: String?) -> PayInOutcome {
        PayInOutcome(
            code: "A0000",
            reason: "Approved",
            explanation: nil,
            transaction: PayInTransaction(
                paymentTransId: transId,
                gatewayTransId: nil,
                method: "card",
                operation: "Sale"
            ),
            storedMethod: nil,
            summaryRows: [],
            responseJSON: ""
        )
    }
}

@testable import PayabliSDKPayIn
import XCTest

final class PaymentSubmitWordingTests: XCTestCase {
    func testEachOperationNamesItsAction() {
        let expected: [PayabliPayInOperation: (idle: String, busy: String)] = [
            .capture: ("Pay", "Paying…"),
            .authorize: ("Authorize", "Authorizing…"),
            .storePaymentMethod: ("Save", "Saving…")
        ]

        for operation in PayabliPayInOperation.allCases {
            let wording = PayInSubmitWording(operation)
            XCTAssertEqual(wording.idle, expected[operation]?.idle, operation.rawValue)
            XCTAssertEqual(wording.busy, expected[operation]?.busy, operation.rawValue)
        }
    }

    func testWithNoHostWordingTheButtonReadsTheOperation() {
        for operation in PayabliPayInOperation.allCases {
            let wording = PayInSubmitWording(operation)
            XCTAssertEqual(wording.text(hostWording: nil, isSubmitting: false), wording.idle, operation.rawValue)
            XCTAssertEqual(wording.text(hostWording: nil, isSubmitting: true), wording.busy, operation.rawValue)
        }
    }

    func testHostWordingReplacesTheIdleTextOnly() {
        let wording = PayInSubmitWording(.capture)

        XCTAssertEqual(wording.text(hostWording: "Pay now", isSubmitting: false), "Pay now")
        XCTAssertEqual(wording.text(hostWording: "Pay now", isSubmitting: true), "Paying…")
    }

    func testBlankHostWordingReadsTheOperation() {
        let labels = PayabliPayInLabels(submitButton: "  ")

        XCTAssertEqual(
            PayInSubmitWording(.storePaymentMethod).text(hostWording: labels.hostSubmitButton, isSubmitting: false),
            "Save"
        )
    }
}

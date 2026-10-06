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
            XCTAssertEqual(
                PayInSubmitWording.text(showing: operation, submitting: nil, hostWording: nil),
                wording.idle,
                operation.rawValue
            )
            XCTAssertEqual(
                PayInSubmitWording.text(showing: operation, submitting: operation, hostWording: nil),
                wording.busy,
                operation.rawValue
            )
        }
    }

    func testHostWordingReplacesTheIdleTextOnly() {
        XCTAssertEqual(PayInSubmitWording.text(showing: .capture, submitting: nil, hostWording: "Pay now"), "Pay now")
        XCTAssertEqual(PayInSubmitWording.text(showing: .capture, submitting: .capture, hostWording: "Pay now"), "Paying…")
    }

    func testBlankHostWordingReadsTheOperation() {
        let labels = PayabliPayInLabels(submitButton: "  ")

        XCTAssertEqual(
            PayInSubmitWording.text(showing: .storePaymentMethod, submitting: nil, hostWording: labels.hostSubmitButton),
            "Save"
        )
    }

    func testTheBusyTextIsTheSubmittedOperationsNotTheOneShown() {
        XCTAssertEqual(
            PayInSubmitWording.text(showing: .storePaymentMethod, submitting: .capture, hostWording: nil),
            "Paying…"
        )
    }
}

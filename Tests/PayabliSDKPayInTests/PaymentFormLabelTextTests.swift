@testable import PayabliSDKPayIn
import XCTest

final class PaymentFormLabelTextTests: XCTestCase {
    /// The default label text, field for field.
    private static let defaultLabelText: [PayabliPayInField: String] = [
        .cardholderName: "Name on card",
        .cardNumber: "Card number",
        .cardExpiration: "Expiration",
        .cardCvv: "CVV",
        .cardZip: "Postal code",
        .accountHolder: "Account holder",
        .routingNumber: "Routing number",
        .accountNumber: "Account number",
        .accountType: "Account type",
        .accountHolderType: "Holder type",
        .secCode: "SEC code",
        .deviceId: "Device",
        .methodDescription: "Description",
        .firstName: "First name",
        .lastName: "Last name",
        .customerNumber: "Customer number",
        .billingEmail: "Billing email",
        .billingZip: "Billing postal code",
        .amount: "Amount",
        .serviceFee: "Fee",
        .surchargeFee: "Surcharge"
    ]

    func testTheDefaultLabelsAreTheSharedText() {
        let labels = PayabliPayInFormLabels()

        for field in PayabliPayInField.allCases {
            XCTAssertEqual(labels.label(for: field), Self.defaultLabelText[field], field.rawValue)
        }
    }

    func testEverySummaryRowIsLabelledWithTheBareLabel() {
        let labels = PayabliPayInFormLabels()

        XCTAssertEqual(PayabliPayInSummaryRows.labelText(for: .amount, labels: labels), "Amount")
        XCTAssertEqual(PayabliPayInSummaryRows.labelText(for: .serviceFee, labels: labels), "Fee")
        XCTAssertEqual(PayabliPayInSummaryRows.labelText(for: .surchargeFee, labels: labels), "Surcharge")
        XCTAssertEqual(PayabliPayInSummaryRows.totalLabelText(labels: labels), "Total")
    }

    func testABlankHostLabelFallsBackToTheDefault() {
        let labels = PayabliPayInFormLabels(fieldLabels: [.amount: "", .serviceFee: "   ", .surchargeFee: "Extra"])

        XCTAssertEqual(labels.label(for: .amount), "Amount")
        XCTAssertEqual(labels.label(for: .serviceFee), "Fee")
        XCTAssertEqual(labels.label(for: .surchargeFee), "Extra")
    }

    func testBlankIsSeparatorsAndWhitespaceControlsOnly() {
        for blank in ["", " ", "\t\n", "\u{1C}", "\u{1F}", "\u{00A0}", "\u{2028}", "\u{3000}"] {
            XCTAssertTrue(PayabliPayInFormLabels.isBlank(blank), blank.unicodeScalars.map { String($0.value, radix: 16) }.joined())
        }
        for notBlank in ["\u{85}", "\u{200B}", " a "] {
            XCTAssertFalse(PayabliPayInFormLabels.isBlank(notBlank), notBlank.unicodeScalars.map { String($0.value, radix: 16) }.joined())
        }
    }

    func testAHostLabelIsUsedAsGiven() {
        let labels = PayabliPayInFormLabels(fieldLabels: [.cardNumber: " Card # "])

        XCTAssertEqual(labels.label(for: .cardNumber), " Card # ")
    }

    func testAnAbsentOrBlankTitleDrawsNoHeading() {
        for title in [nil, "", "   ", "\u{3000}"] {
            XCTAssertNil(PayabliPayInFormLabels(title: title).drawnTitle, String(describing: title))
        }
        XCTAssertEqual(PayabliPayInFormLabels(title: " Checkout ").drawnTitle, "Checkout")
    }

    func testAnAbsentOrBlankButtonWordingIsNotTheHosts() {
        for wording in [nil, "", "\t\n"] {
            XCTAssertNil(PayabliPayInFormLabels(submitButton: wording).hostSubmitButton, String(describing: wording))
        }
        XCTAssertEqual(PayabliPayInFormLabels(submitButton: " Pay now ").hostSubmitButton, "Pay now")
    }
}

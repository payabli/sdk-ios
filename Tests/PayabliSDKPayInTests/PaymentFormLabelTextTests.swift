import PayabliSDKPayIn
import XCTest

final class PaymentFormLabelTextTests: XCTestCase {
    /// The Android SDK's default label text, field for field.
    private static let sharedLabelText: [PayabliPayInField: String] = [
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
        let labels = PayabliPayInLabels()

        for field in PayabliPayInField.allCases {
            XCTAssertEqual(labels.label(for: field), Self.sharedLabelText[field], field.rawValue)
        }
    }

    func testEverySummaryRowIsLabelledWithTheBareLabel() {
        let summary = PayabliPayInPaymentSummaryConfiguration()
        let labels = PayabliPayInLabels()

        XCTAssertEqual(summary.labelText(for: .amount, labels: labels), "Amount")
        XCTAssertEqual(summary.labelText(for: .serviceFee, labels: labels), "Fee")
        XCTAssertEqual(summary.labelText(for: .surchargeFee, labels: labels), "Surcharge")
        XCTAssertEqual(summary.totalLabelText(labels: labels), "Total")
    }

    func testABlankHostLabelFallsBackToTheDefault() {
        let labels = PayabliPayInLabels(fieldLabels: [.amount: "", .serviceFee: "   ", .surchargeFee: "Extra"])

        XCTAssertEqual(labels.label(for: .amount), "Amount")
        XCTAssertEqual(labels.label(for: .serviceFee), "Fee")
        XCTAssertEqual(labels.label(for: .surchargeFee), "Extra")
    }

    func testAHostLabelIsUsedAsGiven() {
        let labels = PayabliPayInLabels(fieldLabels: [.cardNumber: " Card # "])

        XCTAssertEqual(labels.label(for: .cardNumber), " Card # ")
    }
}

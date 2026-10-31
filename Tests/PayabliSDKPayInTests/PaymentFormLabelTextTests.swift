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
        let labels = PayabliPayInLabels()

        for field in PayabliPayInField.allCases {
            XCTAssertEqual(labels.label(for: field), Self.defaultLabelText[field], field.rawValue)
        }
    }

    func testEverySummaryRowIsLabelledWithTheBareLabel() {
        let labels = PayabliPayInLabels()

        XCTAssertEqual(PayabliPayInSummaryRows.labelText(for: .amount, labels: labels), "Amount")
        XCTAssertEqual(PayabliPayInSummaryRows.labelText(for: .serviceFee, labels: labels), "Fee")
        XCTAssertEqual(PayabliPayInSummaryRows.labelText(for: .surchargeFee, labels: labels), "Surcharge")
        XCTAssertEqual(PayabliPayInSummaryRows.totalLabelText(labels: labels), "Total")
    }

    func testABlankHostLabelFallsBackToTheDefault() {
        let labels = PayabliPayInLabels(fieldLabels: [.amount: "", .serviceFee: "   ", .surchargeFee: "Extra"])

        XCTAssertEqual(labels.label(for: .amount), "Amount")
        XCTAssertEqual(labels.label(for: .serviceFee), "Fee")
        XCTAssertEqual(labels.label(for: .surchargeFee), "Extra")
    }

    func testBlankIsSeparatorsAndWhitespaceControlsOnly() {
        for blank in ["", " ", "\t\n", "\u{1C}", "\u{1F}", "\u{00A0}", "\u{2028}", "\u{3000}"] {
            XCTAssertTrue(PayabliPayInLabels.isBlank(blank), blank.unicodeScalars.map { String($0.value, radix: 16) }.joined())
        }
        for notBlank in ["\u{85}", "\u{200B}", " a "] {
            XCTAssertFalse(PayabliPayInLabels.isBlank(notBlank), notBlank.unicodeScalars.map { String($0.value, radix: 16) }.joined())
        }
    }

    func testAHostLabelIsUsedAsGiven() {
        let labels = PayabliPayInLabels(fieldLabels: [.cardNumber: " Card # "])

        XCTAssertEqual(labels.label(for: .cardNumber), " Card # ")
    }

    func testAnAbsentOrBlankTitleDrawsNoHeading() {
        for title in [nil, "", "   ", "\u{3000}", "\u{1C}"] {
            XCTAssertNil(PayabliPayInLabels(title: title).drawnTitle, String(describing: title))
        }
    }

    func testAnAbsentOrBlankButtonWordingIsNotTheHosts() {
        for wording in [nil, "", "\t\n", "\u{1C}"] {
            XCTAssertNil(PayabliPayInLabels(submitButton: wording).hostSubmitButton, String(describing: wording))
        }
    }

    // MARK: - A host string is blank by isBlank and drawn as given

    /// Each host string the form draws, read the way the form reads it.
    private static let drawnStrings: [(name: String, read: (String) -> String?)] = [
        ("title", { PayabliPayInLabels(title: $0).drawnTitle }),
        ("subtitle", { PayabliPayInLabels(subtitle: $0).drawnSubtitle }),
        ("submit button", { PayabliPayInLabels(submitButton: $0).hostSubmitButton }),
        ("placeholder", { PayabliPayInLabels(fieldPlaceholders: [.cardNumber: $0]).placeholder(for: .cardNumber) }),
        ("total", { PayabliPayInSummaryRows.totalLabelText(labels: PayabliPayInLabels(total: $0)) }),
        ("section heading", { PayabliPayInFieldSection(title: $0, fields: [.firstName]).heading })
    ]

    func testAFileSeparatorCountsAsNotGiven() {
        for drawn in Self.drawnStrings where drawn.name != "total" {
            XCTAssertNil(drawn.read("\u{1C}"), drawn.name)
        }
        XCTAssertEqual(PayabliPayInSummaryRows.totalLabelText(labels: PayabliPayInLabels(total: "\u{1C}")), "Total")
    }

    func testAZeroWidthSpaceIsDrawn() {
        for drawn in Self.drawnStrings {
            XCTAssertEqual(drawn.read("\u{200B}"), "\u{200B}", drawn.name)
        }
    }

    func testAPaddedStringIsDrawnWithItsSpaces() {
        for drawn in Self.drawnStrings {
            XCTAssertEqual(drawn.read(" Checkout "), " Checkout ", drawn.name)
        }
    }

    func testABlankStringDrawsItsDefault() {
        let blank = PayabliPayInLabels(title: "  ", subtitle: "  ", submitButton: "  ", total: "  ")

        XCTAssertNil(blank.drawnTitle)
        XCTAssertNil(blank.drawnSubtitle)
        XCTAssertNil(PayabliPayInFieldSection(title: "  ", fields: [.firstName]).heading)
        XCTAssertEqual(PayabliPayInFieldSection(title: "  ", fields: [.amount], style: .summary).heading, "Payment")
        XCTAssertEqual(PayabliPayInSummaryRows.totalLabelText(labels: blank), "Total")
        for operation in [PayabliPayInOperation.capture, .authorize, .storePaymentMethod] {
            XCTAssertEqual(
                PayInSubmitWording.text(showing: operation, submitting: nil, hostWording: blank.hostSubmitButton),
                PayInSubmitWording(operation).idle
            )
        }
    }

    func testASectionKeepsItsTitleAsGiven() {
        XCTAssertEqual(PayabliPayInFieldSection(title: " Checkout ", fields: [.firstName]).title, " Checkout ")
        XCTAssertEqual(PayabliPayInFieldSection(title: "\u{1C}", fields: [.firstName]).title, "\u{1C}")
    }

    func testASectionIdFallsBackPastABlankTitle() {
        XCTAssertEqual(PayabliPayInFieldSection(title: "\u{1C}", fields: [.firstName, .lastName]).id, "firstName-lastName")
    }

    func testASectionIdSurvivesReplacingItsFields() {
        let section = PayabliPayInFieldSection(title: " Checkout ", fields: [.firstName])

        XCTAssertEqual(section.replacingFields([.lastName]).id, section.id)
    }

    // MARK: - The sheet's own header

    @MainActor
    private func sheet(
        _ sheetConfiguration: PayabliPayInSheetConfiguration,
        labels: PayabliPayInLabels = PayabliPayInLabels()
    ) -> PayabliPayInSheetContent {
        PayabliPayInSheetContent(
            isPresented: .constant(true),
            component: flowOnSession(),
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card], labels: labels),
            sheetConfiguration: sheetConfiguration,
            style: nil,
            onCompleted: { _ in },
            onError: { _ in }
        )
    }

    @MainActor
    func testTheSheetHeaderIsBlankByIsBlankAndDrawnAsGiven() {
        let blank = sheet(PayabliPayInSheetConfiguration(title: "\u{1C}", subtitle: "\u{1C}", movesFormHeaderToSheetHeader: false))
        XCTAssertNil(blank.sheetTitle)
        XCTAssertNil(blank.sheetSubtitle)

        for given in ["\u{200B}", " Checkout "] {
            let content = sheet(PayabliPayInSheetConfiguration(title: given, subtitle: given))
            XCTAssertEqual(content.sheetTitle, given)
            XCTAssertEqual(content.sheetSubtitle, given)
        }
    }

    @MainActor
    func testABlankSheetHeaderTakesTheFormsAsGiven() {
        let content = sheet(
            PayabliPayInSheetConfiguration(title: "\u{1C}", subtitle: "  ", movesFormHeaderToSheetHeader: true),
            labels: PayabliPayInLabels(title: " Checkout ", subtitle: "\u{200B}")
        )

        XCTAssertEqual(content.sheetTitle, " Checkout ")
        XCTAssertEqual(content.sheetSubtitle, "\u{200B}")
    }

    // MARK: - Strings sent on the wire are not covered

    func testTheFormsOrderDescriptionIsStillTrimmedOnTheWire() {
        let options = PayabliPayInRequestConfiguration(
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 1, currency: "USD"),
            orderDescription: "Configured"
        )
        XCTAssertEqual(options.request(paymentMethod: .cash, orderDescription: " Coffee ").options.orderDescription, "Coffee")
        XCTAssertEqual(options.request(paymentMethod: .cash, orderDescription: "   ").options.orderDescription, "Configured")
    }
}

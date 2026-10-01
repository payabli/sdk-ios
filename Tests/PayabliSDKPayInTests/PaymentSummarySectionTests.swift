@testable import PayabliSDKPayIn
import XCTest

final class PaymentSummarySectionTests: XCTestCase {
    func testPaymentMethodLabelsLeaveTheTotalLabelUnsetByDefault() {
        XCTAssertNil(PayabliPayInLabels().total)
        XCTAssertEqual(PayabliPayInLabels(total: "Amount due").total, "Amount due")
    }

    func testTheTotalRowTakesTheHostLabelOrTotal() {
        let summary = PayabliPayInPaymentSummaryConfiguration()

        XCTAssertEqual(summary.totalLabelText(labels: PayabliPayInLabels()), "Total:")
        XCTAssertEqual(summary.totalLabelText(labels: PayabliPayInLabels(total: "  ")), "Total:")
        XCTAssertEqual(summary.totalLabelText(labels: PayabliPayInLabels(total: "Amount due")), "Amount due:")
    }

    func testASectionTakesInputUnlessMarkedAsTheSummary() {
        XCTAssertEqual(PayabliPayInFieldSection(fields: [.cardNumber]).style, .inputs)
        XCTAssertEqual(PayabliPayInFieldSection(fields: [.amount], style: .summary).style, .summary)
    }

    func testTheDefaultSectionsMarkTheirPaymentSectionAsTheSummary() {
        let configuration = PayabliPayInFormConfiguration(allowedMethods: [.card, .bankAccount])

        let bothMethods: [[PayabliPayInFieldSection]] = [configuration.cardSections, configuration.bankSections]
        for sections in bothMethods {
            XCTAssertEqual(sections.map(\.style), [.inputs, .summary])
            XCTAssertEqual(sections.last?.title, "Payment Information")
        }
    }

    func testThePaymentSectionTheSDKAppendsIsTheSummary() {
        let configuration = PayabliPayInFormConfiguration(
            allowedMethods: [.card],
            cardSections: [
                PayabliPayInFieldSection(fields: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip])
            ]
        )

        XCTAssertEqual(configuration.cardSections.map(\.style), [.inputs, .summary])
        XCTAssertEqual(configuration.cardSections.last?.title, "Payment Information")
    }

    func testARequiredInputFieldIsAppendedToAnInputsSectionNotTheSummary() {
        let configuration = PayabliPayInFormConfiguration(
            allowedMethods: [.bankAccount],
            defaultMethod: .bankAccount,
            requiredFields: [.billingEmail]
        )

        let holding = configuration.bankSections.filter { $0.fields.contains(.billingEmail) }
        XCTAssertEqual(holding.map(\.style), [.inputs])
    }

    func testAHostSummaryWithNoFieldsKeepsItsPlaceAndTitle() {
        let card = PayabliPayInFieldSection(fields: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip])
        let customer = PayabliPayInFieldSection(title: "Customer", fields: [.firstName])
        let configuration = PayabliPayInFormConfiguration(
            allowedMethods: [.card],
            cardSections: [card, PayabliPayInFieldSection(title: "Due today", fields: [], style: .summary), customer]
        )

        XCTAssertEqual(configuration.cardSections.map(\.title), [nil, "Due today", "Customer"])
        XCTAssertEqual(configuration.cardSections.filter { $0.style == .summary }.count, 1)
    }

    func testAnInputFieldListedInTheSummaryIsMovedToTheInputs() {
        let configuration = PayabliPayInFormConfiguration(
            allowedMethods: [.card],
            cardSections: [
                PayabliPayInFieldSection(fields: [.cardholderName, .cardExpiration, .cardCvv, .cardZip]),
                PayabliPayInFieldSection(title: "Due today", fields: [.amount, .cardNumber, .billingZip], style: .summary)
            ]
        )

        let inputs = configuration.cardSections.filter { $0.style == .inputs }.flatMap(\.fields)
        let summary = configuration.cardSections.filter { $0.style == .summary }.flatMap(\.fields)
        XCTAssertTrue(inputs.contains(.cardNumber))
        XCTAssertTrue(inputs.contains(.billingZip))
        XCTAssertFalse(summary.contains(.cardNumber))
        XCTAssertFalse(summary.contains(.billingZip))
    }

    func testTheSummaryListingDecidesTheRowOrderOverAnEarlierInputsSection() {
        let configuration = PayabliPayInFormConfiguration(
            allowedMethods: [.card],
            cardSections: [
                PayabliPayInFieldSection(fields: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip, .serviceFee]),
                PayabliPayInFieldSection(title: "Due today", fields: [.serviceFee, .amount], style: .summary)
            ]
        )
        let drawn = PayInSummaryPlacement.place(
            configuration.cardSections,
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34, serviceFee: 0.5, currency: "USD"),
            summary: configuration.paymentSummary,
            showsBaseAmount: true
        )

        XCTAssertEqual(drawn.last?.rows.map(\.field), [.serviceFee, .amount])
    }

    func testAHostSummaryKeepsItsStyleThroughNormalization() {
        let configuration = PayabliPayInFormConfiguration(
            allowedMethods: [.card],
            cardSections: [
                PayabliPayInFieldSection(fields: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip]),
                PayabliPayInFieldSection(title: "Due today", fields: [.amount], style: .summary)
            ]
        )

        XCTAssertEqual(configuration.cardSections.map(\.style), [.inputs, .summary])
        XCTAssertEqual(configuration.cardSections.last?.title, "Due today")
    }
}

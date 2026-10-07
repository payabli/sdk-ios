@testable import PayabliSDKPayIn
import XCTest

final class PaymentSummarySectionTests: XCTestCase {
    func testPaymentMethodLabelsLeaveTheTotalLabelUnsetByDefault() {
        XCTAssertNil(PayabliPayInLabels().total)
        XCTAssertEqual(PayabliPayInLabels(total: "Amount due").total, "Amount due")
    }

    func testTheTotalRowTakesTheHostLabelOrTotal() {
        let summary = PayabliPayInPaymentSummaryConfiguration()

        XCTAssertEqual(summary.totalLabelText(labels: PayabliPayInLabels()), "Total")
        XCTAssertEqual(summary.totalLabelText(labels: PayabliPayInLabels(total: "  ")), "Total")
        XCTAssertEqual(summary.totalLabelText(labels: PayabliPayInLabels(total: "Amount due")), "Amount due")
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
            XCTAssertNil(sections.last?.title)
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
        XCTAssertNil(configuration.cardSections.last?.title)
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

    func testRowsTheSummaryDoesNotListFollowInTheStandardOrder() {
        let configuration = PayabliPayInFormConfiguration(
            allowedMethods: [.card],
            cardSections: [
                PayabliPayInFieldSection(fields: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip, .serviceFee]),
                PayabliPayInFieldSection(title: "Due today", fields: [.amount], style: .summary)
            ]
        )
        let drawn = PayInSummaryPlacement.place(
            configuration.cardSections,
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34, serviceFee: 0.5, surchargeFee: 0.31),
            summary: configuration.paymentSummary,
            showsBaseAmount: true
        )

        XCTAssertEqual(drawn.last?.rows.map(\.field), [.amount, .serviceFee, .surchargeFee])
    }

    func testAnEarlierSummaryClaimsNoRow() {
        let configuration = PayabliPayInFormConfiguration(
            allowedMethods: [.card],
            cardSections: [
                PayabliPayInFieldSection(fields: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip]),
                PayabliPayInFieldSection(title: "Due today", fields: [.amount], style: .summary),
                PayabliPayInFieldSection(title: "Fees", fields: [.serviceFee], style: .summary)
            ]
        )
        let drawn = PayInSummaryPlacement.place(
            configuration.cardSections,
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34, serviceFee: 0.5, surchargeFee: 0.31),
            summary: configuration.paymentSummary,
            showsBaseAmount: true
        )

        XCTAssertEqual(drawn.filter(\.isSummary).map(\.title), ["Fees"])
        XCTAssertEqual(drawn.last?.rows.map(\.field), [.serviceFee, .amount, .surchargeFee])
    }

    func testAnEarlierSummarySharingTheLastOnesTitleClaimsNoRow() {
        let configuration = PayabliPayInFormConfiguration(
            allowedMethods: [.card],
            cardSections: [
                PayabliPayInFieldSection(fields: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip]),
                PayabliPayInFieldSection(title: "Payment", fields: [.amount], style: .summary),
                PayabliPayInFieldSection(title: "Payment", fields: [.serviceFee], style: .summary)
            ]
        )
        let drawn = PayInSummaryPlacement.place(
            configuration.cardSections,
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34, serviceFee: 0.5, surchargeFee: 0.31),
            summary: configuration.paymentSummary,
            showsBaseAmount: true
        )

        XCTAssertEqual(drawn.last?.rows.map(\.field), [.serviceFee, .amount, .surchargeFee])
    }

    func testAHostSummaryAppendedToTheDefaultSectionsIsTheOneDrawn() {
        let hostSummary = PayabliPayInFieldSection(
            title: "Due today",
            fields: [.surchargeFee, .serviceFee, .amount],
            style: .summary
        )
        let defaults = PayabliPayInFormConfiguration(allowedMethods: [.card]).cardSections
        let configuration = PayabliPayInFormConfiguration(allowedMethods: [.card], cardSections: defaults + [hostSummary])
        let drawn = PayInSummaryPlacement.place(
            configuration.cardSections,
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34, serviceFee: 0.5, surchargeFee: 0.31),
            summary: configuration.paymentSummary,
            showsBaseAmount: true
        )

        XCTAssertEqual(drawn.filter(\.isSummary).map(\.title), ["Due today"])
        XCTAssertEqual(drawn.last?.isSummary, true)
        XCTAssertEqual(drawn.last?.rows.map(\.field), [.surchargeFee, .serviceFee, .amount])
        XCTAssertEqual(configuration.cardSections.last?.fields, [.surchargeFee, .serviceFee, .amount])
    }

    func testAnInputFieldListedInAnEarlierSummaryIsStillMovedToTheInputs() {
        let configuration = PayabliPayInFormConfiguration(
            allowedMethods: [.card],
            cardSections: [
                PayabliPayInFieldSection(fields: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip]),
                PayabliPayInFieldSection(fields: [.amount, .billingEmail], style: .summary),
                PayabliPayInFieldSection(title: "Due today", fields: [], style: .summary)
            ]
        )

        let holding = configuration.cardSections.filter { $0.fields.contains(.billingEmail) }
        XCTAssertEqual(holding.map(\.style), [.inputs])
    }

    func testAMoneyFieldTheHostLeftOutIsAddedToTheLastSummary() {
        let configuration = PayabliPayInFormConfiguration(
            allowedMethods: [.card],
            cardSections: [
                PayabliPayInFieldSection(fields: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip]),
                PayabliPayInFieldSection(fields: [], style: .summary),
                PayabliPayInFieldSection(title: "Due today", fields: [.serviceFee], style: .summary)
            ]
        )

        XCTAssertEqual(configuration.cardSections.last?.fields, [.serviceFee, .amount, .surchargeFee])
        XCTAssertEqual(configuration.cardSections.filter { $0.style == .summary }.first?.fields, [])
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

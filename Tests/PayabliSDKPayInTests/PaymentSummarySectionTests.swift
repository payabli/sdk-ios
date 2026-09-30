import PayabliSDKPayIn
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

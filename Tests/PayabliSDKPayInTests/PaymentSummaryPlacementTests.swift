@testable import PayabliSDKPayIn
import XCTest

final class PaymentSummaryPlacementTests: XCTestCase {
    private let card = PayabliPayInFieldSection(
        title: "Card",
        fields: [.cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip]
    )
    private let customer = PayabliPayInFieldSection(title: "Customer", fields: [.firstName, .lastName])

    private func summary(_ fields: [PayabliPayInField], title: String? = "Due today") -> PayabliPayInFieldSection {
        PayabliPayInFieldSection(title: title, fields: fields, style: .summary)
    }

    private func details(
        _ totalAmount: Double,
        fee: Double? = nil,
        surcharge: Double? = nil
    ) -> PayabliPayInPaymentDetails {
        PayabliPayInPaymentDetails(totalAmount: totalAmount, serviceFee: fee, surchargeFee: surcharge, currency: "USD")
    }

    private func place(
        _ sections: [PayabliPayInFieldSection],
        _ paymentDetails: PayabliPayInPaymentDetails?,
        showsBaseAmount: Bool = true
    ) -> [PayInDrawnSection] {
        PayInSummaryPlacement.place(
            sections,
            paymentDetails: paymentDetails,
            summary: PayabliPayInPaymentSummaryConfiguration(),
            showsBaseAmount: showsBaseAmount
        )
    }

    private func amount(_ text: String) -> Decimal {
        Decimal(string: text, locale: Locale(identifier: "en_US_POSIX")) ?? .nan
    }

    // MARK: - Where the summary goes

    func testWithNoSummarySectionOneIsAppendedAfterTheInputs() {
        let drawn = place([card, customer], details(12.34, fee: 0.5))

        XCTAssertEqual(drawn.map(\.section.title), ["Card", "Customer", "Payment Information"])
        XCTAssertEqual(drawn.map(\.isSummary), [false, false, true])
    }

    func testTheHostSummaryKeepsItsPlaceItsTitleAndItsOrder() {
        let drawn = place([card, summary([.serviceFee, .amount]), customer], details(12.34, fee: 0.5))

        XCTAssertEqual(drawn.map(\.section.title), ["Card", "Due today", "Customer"])
        XCTAssertEqual(drawn[1].rows.map(\.field), [.serviceFee, .amount])
    }

    func testASummaryThatListsOnlyTheAmountStillShowsEveryFigure() {
        let drawn = place([card, summary([.amount])], details(12.34, fee: 0.5))

        XCTAssertEqual(drawn.last?.rows.map(\.field), [.amount, .serviceFee])
    }

    func testASummaryListingNoFieldsStillPlacesTheAmountsUnderItsTitle() {
        let drawn = place([card, summary([])], details(12.34, fee: 0.5))

        XCTAssertEqual(drawn.last?.section.title, "Due today")
        XCTAssertEqual(drawn.last?.rows.map(\.field), [.amount, .serviceFee])
    }

    func testASecondSummarySectionIsNotDrawn() {
        let drawn = place([card, summary([.amount]), summary([.serviceFee], title: "Fees")], details(12.34, fee: 0.5))

        XCTAssertEqual(drawn.map(\.section.title), ["Card", "Due today"])
    }

    func testAMoneyFieldListedAmongTheInputsIsDrawnInTheSummary() {
        let mixed = PayabliPayInFieldSection(title: "Card", fields: [.cardNumber, .amount])
        let drawn = place([mixed], details(12.34, fee: 0.5))

        XCTAssertEqual(drawn.first?.section.fields, [.cardNumber])
        XCTAssertEqual(drawn.last?.rows.map(\.field), [.amount, .serviceFee])
    }

    func testNothingButZeroOrNothingChargedDrawsNoSummary() {
        XCTAssertEqual(place([card, summary([.amount])], details(0)).map(\.isSummary), [false])
        XCTAssertEqual(place([card, summary([.amount])], nil).map(\.isSummary), [false])
    }

    // MARK: - Which rows

    func testTheAmountIsTheChargeLessTheFeeAndTheTotalIsTheCharge() {
        let drawn = place([card], details(12.34, fee: 0.5)).last

        XCTAssertEqual(drawn?.rows, [
            PayInDrawnSection.Row(field: .amount, amount: amount("11.84")),
            PayInDrawnSection.Row(field: .serviceFee, amount: amount("0.5"))
        ])
        XCTAssertEqual(drawn?.total, amount("12.34"))
    }

    func testOnASurchargedChargeTheTotalAddsTheSurcharge() {
        let drawn = place([card], details(12.34, surcharge: 0.31)).last

        XCTAssertEqual(drawn?.rows.map(\.field), [.amount, .surchargeFee])
        XCTAssertEqual(drawn?.total, amount("12.65"))
    }

    func testWithNothingTakenOutOfTheChargeOnlyTheTotalIsDrawn() {
        let drawn = place([card], details(12.34)).last

        XCTAssertEqual(drawn?.rows, [])
        XCTAssertEqual(drawn?.total, amount("12.34"))
    }

    func testWithTheBaseAmountOffTheFeeTheSurchargeAndTheTotalAreDrawn() {
        let drawn = place([card], details(12.34, fee: 0.5), showsBaseAmount: false).last

        XCTAssertEqual(drawn?.rows.map(\.field), [.serviceFee])
        XCTAssertEqual(drawn?.total, amount("12.34"))
    }

    func testANegativeSurchargeThatCancelsTheChargeDrawsTheRowsAndNoTotal() {
        let drawn = place([card], details(12.34, surcharge: -12.34)).last

        XCTAssertEqual(drawn?.rows.map(\.field), [.amount, .surchargeFee])
        XCTAssertNil(drawn?.total)
    }

    func testAnAmountThatCannotBeSentDrawsNoRowRatherThanFailingTheForm() {
        let drawn = place([card], details(12.34, fee: .infinity)).last

        XCTAssertEqual(drawn?.rows, [])
        XCTAssertEqual(drawn?.total, amount("12.34"))
    }
}

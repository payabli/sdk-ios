import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

final class PaymentMethodSurchargeRowTests: XCTestCase {
    @MainActor
    func testADefaultFormDrawsTheSurchargeRowWhenTheRequestCarriesOne() {
        let view = captureForm(paymentDetails: PayabliPayInPaymentDetails(
            totalAmount: 12.34,
            surchargeFee: 0.30
        ))

        XCTAssertTrue(
            view.drawnSections.contains { $0.rows.contains { $0.field == .surchargeFee } },
            "a surcharge the request carries draws its row"
        )
    }

    @MainActor
    func testTheFormDrawsTheFiguresTheReadersReturn() throws {
        let paymentDetails = PayabliPayInPaymentDetails(totalAmount: 10.30, surchargeFee: 0.30)
        let view = captureForm(paymentDetails: paymentDetails)
        let summary = try XCTUnwrap(view.drawnSections.last { $0.isSummary })
        let read = summary.rows.map { row in
            PayabliPayInSummaryRows.rowAmount(for: row.field, paymentDetails: paymentDetails)
        }

        XCTAssertEqual(summary.rows.map(\.field), [.amount, .surchargeFee])
        XCTAssertEqual(summary.rows.map(\.amount), [Decimal(string: "10"), Decimal(string: "0.3")])
        XCTAssertEqual(read, summary.rows.map(\.amount))
        XCTAssertEqual(summary.total, Decimal(string: "10.3"))
        XCTAssertEqual(PayabliPayInSummaryRows.totalRowAmount(paymentDetails: paymentDetails), summary.total)
    }

    @MainActor
    func testADefaultFormWithoutASurchargeDrawsNoSurchargeRow() {
        let view = captureForm(paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34))

        XCTAssertFalse(
            view.drawnSections.contains { $0.rows.contains { $0.field == .surchargeFee } },
            "an absent surcharge draws no row and no label"
        )
    }

    @MainActor
    func testAZeroSurchargeDrawsNoRow() {
        let view = captureForm(paymentDetails: PayabliPayInPaymentDetails(
            totalAmount: 12.34,
            surchargeFee: 0
        ))

        XCTAssertFalse(
            view.drawnSections.contains { $0.rows.contains { $0.field == .surchargeFee } },
            "a zero surcharge draws no row"
        )
    }

    @MainActor
    func testANegativeSurchargeDrawsItsRow() {
        let view = captureForm(paymentDetails: PayabliPayInPaymentDetails(
            totalAmount: 12.34,
            surchargeFee: -0.30
        ))

        XCTAssertTrue(
            view.drawnSections.contains { $0.rows.contains { $0.field == .surchargeFee } },
            "a negative surcharge draws as the minus figure it is"
        )
    }

    @MainActor
    private func captureForm(paymentDetails: PayabliPayInPaymentDetails) -> PayabliPayInView {
        let component = flowOnSession(
            operation: .capture,
            requestConfiguration: PayabliPayInRequestConfiguration(paymentDetails: paymentDetails)
        )
        return PayabliPayInView(
            component: component,
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card]),
            onCompleted: { _ in }
        )
    }
}

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
            view.activeSections.contains { $0.fields.contains(.surchargeFee) },
            "a surcharge the request carries draws its row"
        )
    }

    @MainActor
    func testADefaultFormWithoutASurchargeDrawsNoSurchargeRow() {
        let view = captureForm(paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34))

        XCTAssertFalse(
            view.activeSections.contains { $0.fields.contains(.surchargeFee) },
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
            view.activeSections.contains { $0.fields.contains(.surchargeFee) },
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
            view.activeSections.contains { $0.fields.contains(.surchargeFee) },
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

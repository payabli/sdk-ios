@testable import PayabliSDKPayIn
import XCTest

final class PaymentMethodStoreRouteFieldTests: XCTestCase {
    @MainActor
    func testTheStoreRouteDropsEveryMoneyRow() {
        let component = flowOnSession(operation: .storePaymentMethod)
        let configuration = PayabliPayInFormConfiguration(
            allowedMethods: [.card],
            cardFieldOrder: [.surchargeFee] + PayabliPayInFormConfiguration.defaultCardFieldOrder
        )
        let viewModel = PayabliPayInViewModel(
            component: component,
            configuration: configuration
        )
        let view = PayabliPayInView(
            component: component,
            configuration: configuration,
            onCompleted: { _ in }
        )

        for moneyField in [PayabliPayInField.amount, .serviceFee, .surchargeFee] {
            XCTAssertFalse(
                viewModel.activeFields.contains(moneyField),
                "a stored method charges nothing, so \(moneyField.rawValue) draws no row"
            )
            XCTAssertFalse(
                view.drawnSections.contains { $0.section.fields.contains(moneyField) || $0.rows.contains { $0.field == moneyField } },
                "a stored method charges nothing, so \(moneyField.rawValue) draws no row"
            )
        }

        XCTAssertTrue(viewModel.activeFields.contains(.cardNumber))
        XCTAssertTrue(view.drawnSections.contains { $0.section.fields.contains(.cardNumber) })
    }
}

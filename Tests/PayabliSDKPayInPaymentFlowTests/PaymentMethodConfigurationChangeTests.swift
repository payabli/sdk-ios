@testable import PayabliSDKPayInPaymentFlow
import SwiftUI
import UIKit
import XCTest

/// A host hands a form that is already on screen a new configuration, the way a SwiftUI parent does
/// when its state changes: same view type in the same place, so the form keeps its identity.
@MainActor
final class PaymentMethodConfigurationChangeTests: XCTestCase {
    func testWithdrawnMethodLeavesTheFormOnTheFirstRenderAfterTheChange() {
        let component = flowOnSession()
        let host = hostedForm(component: component, configuration: configuration(allowedMethods: [.card, .bankAccount]))
        XCTAssertEqual(host.view.payabliSubviews(of: UISegmentedControl.self).count, 1)

        host.rootView = form(component: component, configuration: configuration(allowedMethods: [.card]))
        render(host)

        XCTAssertEqual(host.view.payabliSubviews(of: UISegmentedControl.self).count, 0)
    }

    func testEachChangeAppliesItsOwnConfigurationRatherThanThePreviousOne() {
        let component = flowOnSession()
        let host = hostedForm(component: component, configuration: configuration(allowedMethods: [.card, .bankAccount]))

        host.rootView = form(component: component, configuration: configuration(allowedMethods: [.card]))
        render(host)
        host.rootView = form(component: component, configuration: configuration(allowedMethods: [.card, .bankAccount]))
        render(host)

        XCTAssertEqual(host.view.payabliSubviews(of: UISegmentedControl.self).count, 1)
    }

    /// The summary row is SwiftUI text, which a hosted unit test cannot read back, so this asserts on
    /// the view model the form renders it from. The hosted method tests above cover delivery.
    func testChangedSummaryLabelReplacesThePreviousOneAndKeepsTypedEntry() {
        let component = captureComponent()
        let viewModel = PayabliPayInPaymentFlowViewModel(
            component: component,
            configuration: configuration(amountLabel: "Order total")
        )
        viewModel.cardholderName = "Ada Lovelace"

        viewModel.update(component: component, configuration: configuration(amountLabel: "Due today"))

        XCTAssertEqual(viewModel.paymentSummaryLabelText(for: .amount), "Due today")
        XCTAssertEqual(viewModel.cardholderName, "Ada Lovelace")
    }

    func testTypedEntrySurvivesAChangeThatKeepsItsField() throws {
        let component = flowOnSession()
        let host = hostedForm(component: component, configuration: configuration(allowedMethods: [.card, .bankAccount]))
        let nameField = try XCTUnwrap(textField(labelled: "Name on card", in: host))
        type("Ada Lovelace", into: nameField)
        render(host)

        host.rootView = form(component: component, configuration: configuration(allowedMethods: [.card]))
        render(host)

        XCTAssertEqual(textField(labelled: "Name on card", in: host)?.text, "Ada Lovelace")
    }

    // MARK: - Fixtures

    private func configuration(
        allowedMethods: [PayabliPayInPaymentFlowMethodType] = [.card],
        amountLabel: String? = nil
    ) -> PayabliPayInPaymentFlowFormConfiguration {
        PayabliPayInPaymentFlowFormConfiguration(
            allowedMethods: allowedMethods,
            defaultMethod: .card,
            cardFieldOrder: [.amount] + PayabliPayInPaymentFlowFormConfiguration.defaultCardFieldOrder,
            paymentSummary: PayabliPayInPaymentFlowPaymentSummaryConfiguration(amountLabelText: amountLabel)
        )
    }

    private func captureComponent() -> PayabliPayInPaymentFlow {
        flowOnSession(
            operation: .capture,
            requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration(
                paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 15)
            )
        )
    }

    private func form(
        component: PayabliPayInPaymentFlow,
        configuration: PayabliPayInPaymentFlowFormConfiguration
    ) -> PayabliPayInPaymentFlowView {
        PayabliPayInPaymentFlowView(
            component: component,
            configuration: configuration,
            onCompleted: { _ in }
        )
    }

    private func hostedForm(
        component: PayabliPayInPaymentFlow,
        configuration: PayabliPayInPaymentFlowFormConfiguration
    ) -> UIHostingController<PayabliPayInPaymentFlowView> {
        let host = UIHostingController(rootView: form(component: component, configuration: configuration))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        render(host)
        return host
    }

    /// One layout pass, with no run-loop turn after it: what the payer sees first after the change.
    private func render(_ host: UIHostingController<PayabliPayInPaymentFlowView>) {
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
    }

    private func textField(
        labelled label: String,
        in host: UIHostingController<PayabliPayInPaymentFlowView>
    ) -> UITextField? {
        host.view.payabliSubviews(of: UITextField.self).first { $0.accessibilityLabel == label }
    }

    private func type(_ text: String, into field: UITextField) {
        let length = field.text?.utf16.count ?? 0
        _ = field.delegate?.textField?(
            field,
            shouldChangeCharactersIn: NSRange(location: 0, length: length),
            replacementString: text
        )
    }
}

private extension UIView {
    func payabliSubviews<View: UIView>(of type: View.Type) -> [View] {
        subviews.flatMap { subview -> [View] in
            let own: [View] = (subview as? View).map { [$0] } ?? []
            return own + subview.payabliSubviews(of: type)
        }
    }
}

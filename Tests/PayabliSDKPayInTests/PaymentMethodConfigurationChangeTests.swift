@testable import PayabliSDKPayIn
import SwiftUI
import UIKit
import XCTest

/// A host hands a form that is already on screen a new configuration, the way a SwiftUI parent does
/// when its state changes: same view type in the same place, so the form keeps its identity.
@MainActor
final class PaymentMethodConfigurationChangeTests: XCTestCase {
    func testWithdrawnMethodLeavesTheFormOnTheFirstRenderAfterTheChange() {
        let payIn = flowOnSession()
        let host = hostedForm(payIn: payIn, configuration: configuration(allowedMethods: [.card, .bankAccount]))
        XCTAssertEqual(host.view.payabliSubviews(of: UISegmentedControl.self).count, 1)

        host.rootView = form(payIn: payIn, configuration: configuration(allowedMethods: [.card]))
        render(host)

        XCTAssertEqual(host.view.payabliSubviews(of: UISegmentedControl.self).count, 0)
    }

    func testEachChangeAppliesItsOwnConfigurationRatherThanThePreviousOne() {
        let payIn = flowOnSession()
        let host = hostedForm(payIn: payIn, configuration: configuration(allowedMethods: [.card, .bankAccount]))

        host.rootView = form(payIn: payIn, configuration: configuration(allowedMethods: [.card]))
        render(host)
        host.rootView = form(payIn: payIn, configuration: configuration(allowedMethods: [.card, .bankAccount]))
        render(host)

        XCTAssertEqual(host.view.payabliSubviews(of: UISegmentedControl.self).count, 1)
    }

    /// The summary row is SwiftUI text, which a hosted unit test cannot read back, so this asserts on
    /// the view model the form renders it from. The hosted method tests above cover delivery.
    func testChangedSummaryLabelReplacesThePreviousOneAndKeepsTypedEntry() {
        let component = captureComponent()
        let viewModel = PayabliPayInViewModel(
            component: component,
            operation: .capture,
            configuration: configuration(),
            labels: labels(amountLabel: "Order total")
        )
        viewModel.cardholderName = "Ada Lovelace"

        viewModel.update(
            component: component,
            operation: .capture,
            configuration: configuration(),
            labels: labels(amountLabel: "Due today")
        )

        XCTAssertEqual(viewModel.paymentSummaryLabelText(for: .amount), "Due today")
        XCTAssertEqual(viewModel.cardholderName, "Ada Lovelace")
    }

    func testTypedEntrySurvivesAChangeThatKeepsItsField() throws {
        let payIn = flowOnSession()
        let host = hostedForm(payIn: payIn, configuration: configuration(allowedMethods: [.card, .bankAccount]))
        let nameField = try XCTUnwrap(textField(labelled: "Name on card", in: host))
        type("Ada Lovelace", into: nameField)
        render(host)

        host.rootView = form(payIn: payIn, configuration: configuration(allowedMethods: [.card]))
        render(host)

        XCTAssertEqual(textField(labelled: "Name on card", in: host)?.text, "Ada Lovelace")
    }

    func testChangingTheBaseAmountSwitchAloneIsAConfigurationChange() {
        let withBaseAmount = PayInPaymentFlowConfigurationChange(
            configuration(showsBaseAmount: true),
            labels: PayabliPayInFormLabels()
        )
        let withoutBaseAmount = PayInPaymentFlowConfigurationChange(
            configuration(showsBaseAmount: false),
            labels: PayabliPayInFormLabels()
        )

        XCTAssertNotEqual(withBaseAmount, withoutBaseAmount)
    }

    @MainActor
    func testTheSheetHeaderMoveKeepsTheBaseAmountSwitch() {
        let payIn = flowOnSession()
        let content = PayabliPayInSheetContent(
            isPresented: .constant(true),
            payIn: payIn,
            operation: .storePaymentMethod,
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.card],
                showsBaseAmount: false
            ),
            labels: PayabliPayInFormLabels(),
            sheetConfiguration: PayabliPayInSheetConfiguration(movesFormHeaderToSheetHeader: true),
            style: nil,
            onCompleted: { _ in },
            onFailed: { _ in },
            onMethodChanged: { _ in }
        )

        XCTAssertFalse(
            content.configuration.showsBaseAmount,
            "the sheet hands the form the configuration it was given, so the switch a host set must survive the move"
        )
    }

    func testChangingTheTotalLabelAloneIsAConfigurationChange() {
        let before = PayInPaymentFlowConfigurationChange(
            PayabliPayInFormConfiguration(allowedMethods: [.card]),
            labels: PayabliPayInFormLabels()
        )
        let after = PayInPaymentFlowConfigurationChange(
            PayabliPayInFormConfiguration(allowedMethods: [.card]),
            labels: PayabliPayInFormLabels(total: "Amount due")
        )

        XCTAssertNotEqual(before, after)
    }

    @MainActor
    func testTheSheetHeaderMoveKeepsTheTotalLabel() {
        let payIn = flowOnSession()
        let content = PayabliPayInSheetContent(
            isPresented: .constant(true),
            payIn: payIn,
            operation: .storePaymentMethod,
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card]),
            labels: PayabliPayInFormLabels(total: "Amount due"),
            sheetConfiguration: PayabliPayInSheetConfiguration(movesFormHeaderToSheetHeader: true),
            style: nil,
            onCompleted: { _ in },
            onFailed: { _ in },
            onMethodChanged: { _ in }
        )

        XCTAssertEqual(content.formLabels.total, "Amount due")
    }

    @MainActor
    func testTheSheetHeaderMoveKeepsTheFailureMessages() {
        let payIn = flowOnSession()
        let content = PayabliPayInSheetContent(
            isPresented: .constant(true),
            payIn: payIn,
            operation: .storePaymentMethod,
            configuration: PayabliPayInFormConfiguration(allowedMethods: [.card]),
            labels: PayabliPayInFormLabels(
                declinedMessage: "That card didn't work.",
                retryLaterMessage: "It's busy right now. Try once more.",
                outcomeUnknownMessage: "We can't tell whether that went through.",
                otherMessage: "Something went wrong on our side."
            ),
            sheetConfiguration: PayabliPayInSheetConfiguration(movesFormHeaderToSheetHeader: true),
            style: nil,
            onCompleted: { _ in },
            onFailed: { _ in },
            onMethodChanged: { _ in }
        )

        XCTAssertEqual(content.formLabels.declinedMessage, "That card didn't work.")
        XCTAssertEqual(content.formLabels.retryLaterMessage, "It's busy right now. Try once more.")
        XCTAssertEqual(content.formLabels.outcomeUnknownMessage, "We can't tell whether that went through.")
        XCTAssertEqual(content.formLabels.otherMessage, "Something went wrong on our side.")
    }

    func testChangingTheShowsFailureMessageSwitchAloneIsAConfigurationChange() {
        let drawingIt = PayInPaymentFlowConfigurationChange(
            PayabliPayInFormConfiguration(allowedMethods: [.card], showsFailureMessage: true),
            labels: PayabliPayInFormLabels()
        )
        let hidingIt = PayInPaymentFlowConfigurationChange(
            PayabliPayInFormConfiguration(allowedMethods: [.card], showsFailureMessage: false),
            labels: PayabliPayInFormLabels()
        )

        XCTAssertNotEqual(drawingIt, hidingIt)
    }

    func testChangingAFailureMessageLabelAloneIsAConfigurationChange() {
        let plain = PayabliPayInFormLabels()
        let withEachFailureMessage = [
            PayabliPayInFormLabels(declinedMessage: "That card didn't work."),
            PayabliPayInFormLabels(retryLaterMessage: "It's busy right now. Try once more."),
            PayabliPayInFormLabels(outcomeUnknownMessage: "We can't tell whether that went through."),
            PayabliPayInFormLabels(otherMessage: "Something went wrong on our side.")
        ]

        for labels in withEachFailureMessage {
            XCTAssertNotEqual(
                PayInPaymentFlowConfigurationChange(
                    PayabliPayInFormConfiguration(allowedMethods: [.card]),
                    labels: plain
                ),
                PayInPaymentFlowConfigurationChange(
                    PayabliPayInFormConfiguration(allowedMethods: [.card]),
                    labels: labels
                )
            )
        }
    }

    // MARK: - Fixtures

    private func configuration(
        allowedMethods: [PayabliPayInMethodType] = [.card],
        showsBaseAmount: Bool = true
    ) -> PayabliPayInFormConfiguration {
        PayabliPayInFormConfiguration(
            allowedMethods: allowedMethods,
            defaultMethod: .card,
            cardFieldOrder: [.amount] + PayabliPayInFormConfiguration.defaultCardFieldOrder,
            showsBaseAmount: showsBaseAmount
        )
    }

    private func labels(amountLabel: String? = nil) -> PayabliPayInFormLabels {
        PayabliPayInFormLabels(
            fieldLabels: amountLabel.map { [.amount: $0] } ?? PayabliPayInFormLabels.defaultFieldLabels
        )
    }

    private func captureComponent() -> PayabliPayIn {
        flowOnSession(
            operation: .capture,
            requestConfiguration: PayabliPayInRequestConfiguration(
                paymentDetails: PayabliPayInPaymentDetails(totalAmount: 15)
            )
        )
    }

    private func form(
        payIn: PayabliPayIn,
        configuration: PayabliPayInFormConfiguration
    ) -> PayabliPayInForm {
        PayabliPayInForm(
            payIn: payIn,
            operation: .storePaymentMethod,
            configuration: configuration,
            labels: PayabliPayInFormLabels(),
            onCompleted: { _ in },
            onFailed: { _ in },
            onMethodChanged: { _ in }
        )
    }

    private func hostedForm(
        payIn: PayabliPayIn,
        configuration: PayabliPayInFormConfiguration
    ) -> UIHostingController<PayabliPayInForm> {
        let host = UIHostingController(rootView: form(payIn: payIn, configuration: configuration))
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        render(host)
        return host
    }

    /// One layout pass, with no run-loop turn after it: what the payer sees first after the change.
    private func render(_ host: UIHostingController<PayabliPayInForm>) {
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
    }

    private func textField(
        labelled label: String,
        in host: UIHostingController<PayabliPayInForm>
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

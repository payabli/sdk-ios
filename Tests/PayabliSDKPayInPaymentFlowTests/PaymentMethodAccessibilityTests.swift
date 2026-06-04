@testable import PayabliSDKPayInPaymentFlow
import SwiftUI
import UIKit
import XCTest

final class PaymentMethodAccessibilityTests: XCTestCase {
    func testInputAndButtonStylesPreserveMinimumTouchTargets() {
        let inputSize = PayabliPayInPaymentFlowInputSize(height: 1)
        let submitStyle = PayabliPayInPaymentFlowSubmitButtonStyle(height: 1)

        XCTAssertEqual(inputSize.height, PayabliPayInPaymentFlowAccessibility.minimumTouchTarget)
        XCTAssertEqual(submitStyle.height, PayabliPayInPaymentFlowAccessibility.minimumTouchTarget)
    }

    func testAccessibilityTextFieldValuesDoNotRepeatEmptyPlaceholders() {
        XCTAssertEqual(
            PayabliPayInPaymentFlowAccessibility.textFieldValue(text: "", isSecure: false),
            "Empty"
        )
        XCTAssertEqual(
            PayabliPayInPaymentFlowAccessibility.textFieldValue(text: "Card number", isSecure: false),
            "Card number"
        )
        XCTAssertEqual(
            PayabliPayInPaymentFlowAccessibility.textFieldValue(text: "123", isSecure: true),
            "Entered"
        )
    }

    func testAccessibilityHintsAndAnnouncementsDescribeControlState() {
        XCTAssertEqual(
            PayabliPayInPaymentFlowAccessibility.expirationValue(
                displayText: "MM/YY",
                hasSelectedExpiration: false
            ),
            "No expiration selected"
        )
        XCTAssertEqual(
            PayabliPayInPaymentFlowAccessibility.expirationHint(format: "MM/YY"),
            "Opens month and year picker. Expected format MM/YY."
        )
        XCTAssertEqual(
            PayabliPayInPaymentFlowAccessibility.pickerHint(label: "Account type"),
            "Opens account type options."
        )
        XCTAssertEqual(
            PayabliPayInPaymentFlowAccessibility.submitValue(canSubmit: false, isSubmitting: false),
            "Disabled"
        )
        XCTAssertEqual(
            PayabliPayInPaymentFlowAccessibility.submitValue(canSubmit: true, isSubmitting: false),
            ""
        )
        XCTAssertEqual(
            PayabliPayInPaymentFlowAccessibility.submitValue(canSubmit: true, isSubmitting: true),
            "In progress"
        )
        XCTAssertEqual(
            PayabliPayInPaymentFlowAccessibility.submitHint(canSubmit: false, isSubmitting: false),
            "Complete the required fields before saving."
        )
        XCTAssertEqual(
            PayabliPayInPaymentFlowAccessibility.submitHint(canSubmit: true, isSubmitting: false),
            "Saves the payment method."
        )
        XCTAssertEqual(
            PayabliPayInPaymentFlowAccessibility.submitHint(canSubmit: true, isSubmitting: true),
            "Saving payment method."
        )
        XCTAssertEqual(
            PayabliPayInPaymentFlowAccessibility.errorAnnouncement(for: "Unable to save"),
            "Error: Unable to save"
        )
        XCTAssertEqual(
            PayabliPayInPaymentFlowAccessibility.fieldErrorAnnouncement(
                fieldLabel: "Card number",
                message: "Invalid Card Number"
            ),
            "Error in Card number: Invalid Card Number"
        )
    }

    func testCardNumberHintIncludesDetectedBrandAndValidationError() {
        XCTAssertEqual(
            PayabliPayInPaymentFlowAccessibility.cardNumberHint(
                brand: .visa,
                validationMessage: "Invalid Card Number"
            ),
            "Visa detected. Error: Invalid Card Number."
        )
        XCTAssertNil(PayabliPayInPaymentFlowAccessibility.cardNumberHint(
            brand: .unknown,
            validationMessage: nil
        ))
    }

    func testCustomUIFontIsScaledForDynamicType() {
        let baseFont = UIFont.systemFont(ofSize: 13)
        let style = PayabliPayInPaymentFlowInputStyle(uiFont: baseFont)

        XCTAssertGreaterThanOrEqual(style.resolvedUIFont.pointSize, baseFont.pointSize)
    }

    @MainActor
    func testHostedPlaceholderOnlyFieldsExposeLabelsWithoutPlaceholderValues() {
        let component = PayabliPayInPaymentFlow(
            accessToken: "test-token",
            entryPoint: "entry",
            environment: .sandbox
        )
        let hiddenLabelFields: [PayabliPayInPaymentFlowField] = [
            .cardholderName,
            .cardNumber,
            .cardCvv,
            .cardZip
        ]
        let configuration = PayabliPayInPaymentFlowFormConfiguration(
            allowedMethods: [.card],
            labels: PayabliPayInPaymentFlowLabels(
                fieldPlaceholders: Dictionary(uniqueKeysWithValues: hiddenLabelFields.map { field in
                    (
                        field,
                        PayabliPayInPaymentFlowLabels.defaultFieldLabels[field] ?? field.rawValue
                    )
                })
            ),
            showsFieldLabels: false
        )
        let view = PayabliPayInPaymentFlowView(
            component: component,
            configuration: configuration,
            onCompleted: { _ in }
        )
        let host = UIHostingController(rootView: view)
        let window = UIWindow(frame: UIScreen.main.bounds)
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.1))

        let textFields = host.view.payabliAllSubviews.compactMap { $0 as? UITextField }
        let cardNumberField = textFields.first { $0.accessibilityLabel == "Card number" }
        let cvvField = textFields.first { $0.accessibilityLabel == "CVV" }

        XCTAssertNotNil(cardNumberField)
        XCTAssertEqual(cardNumberField?.accessibilityValue, "Empty")
        XCTAssertEqual(
            cardNumberField?.accessibilityIdentifier,
            PayabliPayInPaymentFlowAccessibility.fieldIdentifier(.cardNumber)
        )
        XCTAssertEqual(cvvField?.accessibilityValue, "Empty")
        XCTAssertTrue(cvvField?.isSecureTextEntry == true)
    }
}

private extension UIView {
    var payabliAllSubviews: [UIView] {
        subviews + subviews.flatMap(\.payabliAllSubviews)
    }
}

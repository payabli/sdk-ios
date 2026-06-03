@testable import PayabliSDKPaymentMethod
import SwiftUI
import UIKit
import XCTest

final class PaymentMethodAccessibilityTests: XCTestCase {
    func testInputAndButtonStylesPreserveMinimumTouchTargets() {
        let inputSize = PayabliPaymentMethodInputSize(height: 1)
        let submitStyle = PayabliPaymentMethodSubmitButtonStyle(height: 1)

        XCTAssertEqual(inputSize.height, PayabliPaymentMethodAccessibility.minimumTouchTarget)
        XCTAssertEqual(submitStyle.height, PayabliPaymentMethodAccessibility.minimumTouchTarget)
    }

    func testAccessibilityTextFieldValuesDoNotRepeatEmptyPlaceholders() {
        XCTAssertEqual(
            PayabliPaymentMethodAccessibility.textFieldValue(text: "", isSecure: false),
            "Empty"
        )
        XCTAssertEqual(
            PayabliPaymentMethodAccessibility.textFieldValue(text: "Card number", isSecure: false),
            "Card number"
        )
        XCTAssertEqual(
            PayabliPaymentMethodAccessibility.textFieldValue(text: "123", isSecure: true),
            "Entered"
        )
    }

    func testAccessibilityHintsAndAnnouncementsDescribeControlState() {
        XCTAssertEqual(
            PayabliPaymentMethodAccessibility.expirationValue(
                displayText: "MM/YY",
                hasSelectedExpiration: false
            ),
            "No expiration selected"
        )
        XCTAssertEqual(
            PayabliPaymentMethodAccessibility.expirationHint(format: "MM/YY"),
            "Opens month and year picker. Expected format MM/YY."
        )
        XCTAssertEqual(
            PayabliPaymentMethodAccessibility.pickerHint(label: "Account type"),
            "Opens account type options."
        )
        XCTAssertEqual(
            PayabliPaymentMethodAccessibility.submitValue(canSubmit: false, isSubmitting: false),
            "Disabled"
        )
        XCTAssertEqual(
            PayabliPaymentMethodAccessibility.submitValue(canSubmit: true, isSubmitting: false),
            ""
        )
        XCTAssertEqual(
            PayabliPaymentMethodAccessibility.submitValue(canSubmit: true, isSubmitting: true),
            "In progress"
        )
        XCTAssertEqual(
            PayabliPaymentMethodAccessibility.submitHint(canSubmit: false, isSubmitting: false),
            "Complete the required fields before saving."
        )
        XCTAssertEqual(
            PayabliPaymentMethodAccessibility.submitHint(canSubmit: true, isSubmitting: false),
            "Saves the payment method."
        )
        XCTAssertEqual(
            PayabliPaymentMethodAccessibility.submitHint(canSubmit: true, isSubmitting: true),
            "Saving payment method."
        )
        XCTAssertEqual(
            PayabliPaymentMethodAccessibility.errorAnnouncement(for: "Unable to save"),
            "Error: Unable to save"
        )
        XCTAssertEqual(
            PayabliPaymentMethodAccessibility.fieldErrorAnnouncement(
                fieldLabel: "Card number",
                message: "Invalid Card Number"
            ),
            "Error in Card number: Invalid Card Number"
        )
    }

    func testCardNumberHintIncludesDetectedBrandAndValidationError() {
        XCTAssertEqual(
            PayabliPaymentMethodAccessibility.cardNumberHint(
                brand: .visa,
                validationMessage: "Invalid Card Number"
            ),
            "Visa detected. Error: Invalid Card Number."
        )
        XCTAssertNil(PayabliPaymentMethodAccessibility.cardNumberHint(
            brand: .unknown,
            validationMessage: nil
        ))
    }

    func testCustomUIFontIsScaledForDynamicType() {
        let baseFont = UIFont.systemFont(ofSize: 13)
        let style = PayabliPaymentMethodInputStyle(uiFont: baseFont)

        XCTAssertGreaterThanOrEqual(style.resolvedUIFont.pointSize, baseFont.pointSize)
    }

    @MainActor
    func testHostedPlaceholderOnlyFieldsExposeLabelsWithoutPlaceholderValues() {
        let component = PayabliPaymentMethod(
            accessToken: "test-token",
            entryPoint: "entry",
            environment: .sandbox
        )
        let hiddenLabelFields: [PayabliPaymentMethodField] = [
            .cardholderName,
            .cardNumber,
            .cardCvv,
            .cardZip
        ]
        let configuration = PayabliPaymentMethodFormConfiguration(
            allowedMethods: [.card],
            labels: PayabliPaymentMethodLabels(
                fieldPlaceholders: Dictionary(uniqueKeysWithValues: hiddenLabelFields.map { field in
                    (
                        field,
                        PayabliPaymentMethodLabels.defaultFieldLabels[field] ?? field.rawValue
                    )
                })
            ),
            showsFieldLabels: false
        )
        let view = PayabliPaymentMethodView(
            component: component,
            configuration: configuration,
            onPaymentMethodAdded: { _ in }
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
            PayabliPaymentMethodAccessibility.fieldIdentifier(.cardNumber)
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

@testable import PayabliSDKPayIn
import SwiftUI
import UIKit
import XCTest

final class PaymentMethodAccessibilityTests: XCTestCase {
    func testInputAndButtonStylesPreserveMinimumTouchTargets() {
        let inputSize = PayabliPayInInputSize(height: 1)
        let submitStyle = PayabliPayInSubmitButtonStyle(height: 1)

        XCTAssertEqual(inputSize.height, PayabliPayInAccessibility.minimumTouchTarget)
        XCTAssertEqual(submitStyle.height, PayabliPayInAccessibility.minimumTouchTarget)
    }

    func testAccessibilityTextFieldValuesDoNotRepeatEmptyPlaceholders() {
        XCTAssertEqual(
            PayabliPayInAccessibility.textFieldValue(text: "", isSecure: false),
            "Empty"
        )
        XCTAssertEqual(
            PayabliPayInAccessibility.textFieldValue(text: "Card number", isSecure: false),
            "Card number"
        )
        XCTAssertEqual(
            PayabliPayInAccessibility.textFieldValue(text: "123", isSecure: true),
            "Entered"
        )
    }

    func testAccessibilityHintsAndAnnouncementsDescribeControlState() {
        XCTAssertEqual(
            PayabliPayInAccessibility.expirationValue(
                displayText: "MM/YY",
                hasSelectedExpiration: false
            ),
            "No expiration selected"
        )
        XCTAssertEqual(
            PayabliPayInAccessibility.expirationHint(format: "MM/YY"),
            "Opens month and year picker. Expected format MM/YY."
        )
        XCTAssertEqual(
            PayabliPayInAccessibility.pickerHint(label: "Account type"),
            "Opens account type options."
        )
        XCTAssertEqual(
            PayabliPayInAccessibility.submitValue(canSubmit: false, isSubmitting: false),
            "Disabled"
        )
        XCTAssertEqual(
            PayabliPayInAccessibility.submitValue(canSubmit: true, isSubmitting: false),
            ""
        )
        XCTAssertEqual(
            PayabliPayInAccessibility.submitValue(canSubmit: true, isSubmitting: true),
            "In progress"
        )
        XCTAssertEqual(
            PayabliPayInAccessibility.submitHint(canSubmit: false, isSubmitting: false),
            "Complete the required fields before saving."
        )
        XCTAssertEqual(
            PayabliPayInAccessibility.submitHint(canSubmit: true, isSubmitting: false),
            "Saves the payment method."
        )
        XCTAssertEqual(
            PayabliPayInAccessibility.submitHint(canSubmit: true, isSubmitting: true),
            "Saving payment method."
        )
        XCTAssertEqual(
            PayabliPayInAccessibility.errorAnnouncement(for: "Unable to save"),
            "Error: Unable to save"
        )
        XCTAssertEqual(
            PayabliPayInAccessibility.fieldErrorAnnouncement(
                fieldLabel: "Card number",
                message: "Invalid Card Number"
            ),
            "Error in Card number: Invalid Card Number"
        )
    }

    func testCardNumberHintIncludesDetectedBrandAndValidationError() {
        XCTAssertEqual(
            PayabliPayInAccessibility.cardNumberHint(
                brand: .visa,
                validationMessage: "Invalid Card Number"
            ),
            "Visa detected. Error: Invalid Card Number."
        )
        XCTAssertNil(PayabliPayInAccessibility.cardNumberHint(
            brand: .unknown,
            validationMessage: nil
        ))
    }

    func testCustomUIFontIsScaledForDynamicType() {
        let baseFont = UIFont.systemFont(ofSize: 13)
        let style = PayabliPayInInputStyle(uiFont: baseFont)

        XCTAssertGreaterThanOrEqual(style.resolvedUIFont.pointSize, baseFont.pointSize)
    }

    @MainActor
    func testHostedPlaceholderOnlyFieldsExposeLabelsWithoutPlaceholderValues() {
        let component = flowOnSession(
            token: "test-token",
            entryPoint: "entry",
            environment: .sandbox
        )
        let hiddenLabelFields: [PayabliPayInField] = [
            .cardholderName,
            .cardNumber,
            .cardCvv,
            .cardZip
        ]
        let configuration = PayabliPayInFormConfiguration(
            allowedMethods: [.card],
            labels: PayabliPayInLabels(
                fieldPlaceholders: Dictionary(uniqueKeysWithValues: hiddenLabelFields.map { field in
                    (
                        field,
                        PayabliPayInLabels.defaultFieldLabels[field] ?? field.rawValue
                    )
                })
            ),
            showsFieldLabels: false
        )
        let view = PayabliPayInView(
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
            PayabliPayInAccessibility.fieldIdentifier(.cardNumber)
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

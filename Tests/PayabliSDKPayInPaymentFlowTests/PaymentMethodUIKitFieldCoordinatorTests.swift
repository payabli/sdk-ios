@testable import PayabliSDKPayInPaymentFlow
import SwiftUI
import UIKit
import XCTest

/// Split from `PaymentMethodCoverageExpansionTests` rather than added to it: that class is already
/// at the `type_body_length` ceiling. These exercise `PayabliPayInPaymentFlowUIKitTextField`'s
/// `Coordinator` directly against a bare `UITextField`, with no hosting controller — distinct from
/// the SwiftUI-hosted rendering tests that stayed behind.
final class PaymentMethodUIKitFieldCoordinatorTests: XCTestCase {
    @MainActor
    func testUIKitTextFieldCoordinatorSanitizesAndTracksFocus() {
        var text = "12"
        var focusedField: PayabliPayInPaymentFlowField?
        let field = PayabliPayInPaymentFlowUIKitTextField(
            text: Binding(get: { text }, set: { text = $0 }),
            placeholder: "Card number",
            field: .cardNumber,
            focusedField: Binding(get: { focusedField }, set: { focusedField = $0 }),
            accessibilityLabel: "Card number",
            sanitize: \.digitsOnly
        )
        let coordinator = field.makeCoordinator()
        let textField = UITextField()
        textField.text = "12"

        coordinator.textFieldDidBeginEditing(textField)
        XCTAssertEqual(focusedField, .cardNumber)

        XCTAssertFalse(coordinator.textField(
            textField,
            shouldChangeCharactersIn: NSRange(location: 2, length: 0),
            replacementString: "ab3"
        ))
        XCTAssertEqual(textField.text, "123")
        XCTAssertEqual(text, "123")

        XCTAssertTrue(coordinator.textField(
            textField,
            shouldChangeCharactersIn: NSRange(location: 3, length: 0),
            replacementString: "4"
        ))

        coordinator.editingChanged(textField)
        XCTAssertEqual(text, "123")

        coordinator.textFieldDidEndEditing(textField)
        XCTAssertNil(focusedField)
    }

    @MainActor
    func testUIKitProtectedTextFieldStoresBindingButMasksUIKitText() {
        var text = ""
        var focusedField: PayabliPayInPaymentFlowField?
        let field = PayabliPayInPaymentFlowUIKitTextField(
            text: Binding(get: { text }, set: { text = $0 }),
            placeholder: "Card number",
            field: .cardNumber,
            focusedField: Binding(get: { focusedField }, set: { focusedField = $0 }),
            keyboardType: .numberPad,
            accessibilityLabel: "Card number",
            protectsTextContent: true,
            sanitize: \.digitsOnly
        )
        let coordinator = field.makeCoordinator()
        let textField = UITextField()

        XCTAssertFalse(coordinator.textField(
            textField,
            shouldChangeCharactersIn: NSRange(location: 0, length: 0),
            replacementString: "4111111111111111"
        ))

        XCTAssertEqual(text, "4111111111111111")
        XCTAssertEqual(textField.text, "••••••••••••1111")
        XCTAssertFalse(textField.text?.contains("4111111111111111") == true)
    }

    @MainActor
    func testUIKitProtectedSecureFieldMasksNonCardSensitiveText() {
        var text = ""
        var focusedField: PayabliPayInPaymentFlowField?
        let field = PayabliPayInPaymentFlowUIKitTextField(
            text: Binding(get: { text }, set: { text = $0 }),
            placeholder: "CVV",
            field: .cardCvv,
            focusedField: Binding(get: { focusedField }, set: { focusedField = $0 }),
            keyboardType: .numberPad,
            isSecure: true,
            accessibilityLabel: "CVV",
            protectsTextContent: true,
            sanitize: \.digitsOnly
        )
        let coordinator = field.makeCoordinator()
        let textField = UITextField()

        XCTAssertFalse(coordinator.textField(
            textField,
            shouldChangeCharactersIn: NSRange(location: 0, length: 0),
            replacementString: "123"
        ))

        XCTAssertEqual(text, "123")
        XCTAssertEqual(textField.text, "•••")
        XCTAssertFalse(textField.text?.contains("123") == true)
    }

    @MainActor
    func testUIKitTextFieldDefaultSanitizerAllowsChangesAndRejectsInvalidRanges() {
        var text = "Hello"
        var focusedField: PayabliPayInPaymentFlowField?
        let field = PayabliPayInPaymentFlowUIKitTextField(
            text: Binding(get: { text }, set: { text = $0 }),
            placeholder: "",
            field: .cardholderName,
            focusedField: Binding(get: { focusedField }, set: { focusedField = $0 }),
            accessibilityLabel: "Cardholder name"
        )
        let coordinator = field.makeCoordinator()
        let textField = UITextField()
        textField.text = "Hello"

        XCTAssertFalse(coordinator.textField(
            textField,
            shouldChangeCharactersIn: NSRange(location: 99, length: 0),
            replacementString: "!"
        ))
        XCTAssertTrue(coordinator.textField(
            textField,
            shouldChangeCharactersIn: NSRange(location: 5, length: 0),
            replacementString: "!"
        ))

        coordinator.editingChanged(textField)
        XCTAssertEqual(text, "Hello")
    }
}

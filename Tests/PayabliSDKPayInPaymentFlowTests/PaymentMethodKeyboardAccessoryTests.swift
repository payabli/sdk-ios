@testable import PayabliSDKPayInPaymentFlow
import SwiftUI
import UIKit
import XCTest

/// Which keyboards get a Done bar. The card number, CVV and the two ACH fields
/// use a number pad, which has no return key, so without the bar the keyboard
/// covers the form and nothing on screen takes it back.
final class PaymentMethodKeyboardAccessoryTests: XCTestCase {
    private typealias Field = PayabliPayInPaymentFlowUIKitTextField

    func testKeyboardsWithoutAReturnKeyGetTheBar() {
        for keyboardType in [
            UIKeyboardType.numberPad,
            .decimalPad,
            .phonePad,
            .asciiCapableNumberPad
        ] {
            XCTAssertTrue(
                Field.requiresDoneAccessory(keyboardType),
                "\(keyboardType) has no return key and needs the bar"
            )
        }
    }

    func testKeyboardsWithAReturnKeyDoNot() {
        for keyboardType in [
            UIKeyboardType.default,
            .emailAddress,
            .numbersAndPunctuation,
            .URL,
            .asciiCapable
        ] {
            XCTAssertFalse(
                Field.requiresDoneAccessory(keyboardType),
                "\(keyboardType) already ends editing from the keyboard"
            )
        }
    }

    /// The form's own choices, so this fails if a field is moved onto a keyboard
    /// whose dismissal is not covered.
    func testTheFormsNumericFieldsAreCovered() {
        XCTAssertTrue(Field.requiresDoneAccessory(.numberPad))
        XCTAssertFalse(Field.requiresDoneAccessory(.numbersAndPunctuation))
        XCTAssertFalse(Field.requiresDoneAccessory(.emailAddress))
    }

    // MARK: - The bar itself, and what its Done does

    /// The predicate tests above decide which keyboards want a bar. These cover the
    /// bar that gets built and the control on it, which is what a payer taps.
    func testTheBarCarriesADoneControlAddressableByIdentifier() throws {
        let coordinator = numberPadField().makeCoordinator()

        let bar = coordinator.doneAccessoryView()
        let done = try XCTUnwrap(bar.items?.last)

        XCTAssertEqual(bar.items?.count, 2, "a spacer and the control")
        XCTAssertEqual(done.accessibilityIdentifier, PayabliPayInPaymentFlowAccessibility.keyboardDoneIdentifier)
        XCTAssertNotNil(done.action, "the control does nothing without an action")
    }

    /// One bar per coordinator: reassigning `inputAccessoryView` while the field is
    /// first responder makes UIKit rebuild the input views under whoever is typing.
    func testTheBarIsBuiltOnceAndReused() {
        let coordinator = numberPadField().makeCoordinator()

        XCTAssertTrue(coordinator.doneAccessoryView() === coordinator.doneAccessoryView())
    }

    /// Done resigns the field that owns the bar rather than ending editing across
    /// the application, so the SDK reaches only its own responder.
    func testDoneResignsTheFieldThatOwnsTheBar() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let textField = UITextField(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        window.addSubview(textField)
        window.makeKeyAndVisible()
        let coordinator = numberPadField().makeCoordinator()
        coordinator.textField = textField

        XCTAssertTrue(textField.becomeFirstResponder(), "the field never took first responder")

        coordinator.endEditing()

        XCTAssertFalse(textField.isFirstResponder)
    }

    private func numberPadField() -> PayabliPayInPaymentFlowUIKitTextField {
        PayabliPayInPaymentFlowUIKitTextField(
            text: .constant(""),
            placeholder: "",
            field: .cardNumber,
            focusedField: .constant(nil),
            keyboardType: .numberPad,
            accessibilityLabel: "Card number"
        )
    }
}

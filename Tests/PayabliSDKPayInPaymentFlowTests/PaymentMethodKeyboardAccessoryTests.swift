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

    /// Every field the form renders, against the keyboard the form actually gives
    /// it: one with a return key, or one carrying the bar. Moving a field onto a
    /// keyboard with neither fails here rather than shipping a trapped keyboard.
    func testEveryFieldHasAWayBack() {
        for field in PayabliPayInPaymentFlowField.allCases {
            let keyboard = field.keyboardType

            XCTAssertTrue(
                Field.requiresDoneAccessory(keyboard) || Self.keyboardsWithAReturnKey.contains(keyboard),
                "\(field.rawValue) has no way back from its keyboard"
            )
        }
    }

    /// The form's numeric fields, named, so a field moved off a number pad shows up
    /// here as well as in the sweep above.
    func testTheFormsNumericFieldsAreOnANumberPad() {
        let numeric: [PayabliPayInPaymentFlowField] = [.cardNumber, .cardCvv, .achRouting, .achAccount]
        for field in numeric {
            XCTAssertEqual(field.keyboardType, .numberPad, field.rawValue)
        }
    }

    /// A keyboard that has one dismisses on it, since the coordinator resigns the
    /// field when it is pressed.
    private static let keyboardsWithAReturnKey: [UIKeyboardType] = [
        .default, .asciiCapable, .numbersAndPunctuation, .URL, .emailAddress,
        .namePhonePad, .twitter, .webSearch
    ]

    // MARK: - The bar itself, and what its Done does

    /// The predicate tests above decide which keyboards want a bar. These cover the
    /// bar that gets built and the control on it, which is what a payer taps.
    func testTheBarCarriesADoneControlAddressableByIdentifier() throws {
        let coordinator = numberPadField().makeCoordinator()

        let bar = coordinator.doneAccessoryView()
        let done = try XCTUnwrap(
            bar.subviews.compactMap { $0 as? UIButton }.first,
            "the bar carries no button"
        )

        XCTAssertEqual(done.accessibilityIdentifier, PayabliPayInPaymentFlowAccessibility.keyboardDoneIdentifier)
        XCTAssertEqual(done.accessibilityLabel, PayabliPayInPaymentFlowAccessibility.keyboardDoneLabel)
        XCTAssertNotNil(done.image(for: .normal), "the control shows nothing without an image")
        XCTAssertFalse(
            done.actions(forTarget: coordinator, forControlEvent: .touchUpInside)?.isEmpty ?? true,
            "the control does nothing when tapped"
        )
    }

    /// A bar with no height of its own lays out at zero, which puts a keyboard on
    /// screen with a strip above it and nothing in it.
    func testTheBarIsTallEnoughForItsControl() {
        let bar = numberPadField().makeCoordinator().doneAccessoryView()

        XCTAssertGreaterThanOrEqual(
            bar.frame.height,
            PayabliPayInPaymentFlowAccessibility.minimumTouchTarget
        )
    }

    /// It spans the keyboard rather than floating over the form: a toolbar used as
    /// an accessory draws no background and lays its items out free of one, so this
    /// carries its own material across the full width.
    func testTheBarFillsItsWidthWithTheKeyboardsMaterial() throws {
        let bar = numberPadField().makeCoordinator().doneAccessoryView()
        bar.frame = CGRect(x: 0, y: 0, width: 390, height: bar.frame.height)
        bar.layoutIfNeeded()

        let material = try XCTUnwrap(
            bar.subviews.compactMap { $0 as? UIVisualEffectView }.first,
            "the bar has no material, so it reads as a control floating over the form"
        )

        XCTAssertEqual(material.frame, bar.bounds)
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

    /// A return key resigns the field, so a keyboard that has one needs no bar.
    func testTheReturnKeyResignsTheField() {
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 320, height: 480))
        let textField = UITextField(frame: CGRect(x: 0, y: 0, width: 320, height: 44))
        window.addSubview(textField)
        window.makeKeyAndVisible()
        let coordinator = numberPadField().makeCoordinator()
        textField.delegate = coordinator
        coordinator.textField = textField

        XCTAssertTrue(textField.becomeFirstResponder(), "the field never took first responder")

        XCTAssertFalse(
            coordinator.textFieldShouldReturn(textField),
            "returning true lets UIKit insert a newline into a single-line field"
        )
        XCTAssertFalse(textField.isFirstResponder)
    }

    /// The assignment itself, which the screenshot in `KeyboardDismissalUITests`
    /// shows but cannot assert: a keyboard with no return key gets the bar, and one
    /// that has a return key is left alone.
    func testAFieldGetsTheBarOnlyWhenItsKeyboardHasNoReturnKey() {
        let textField = UITextField()
        let coordinator = numberPadField().makeCoordinator()

        Field.applyAccessory(to: textField, keyboardType: .numberPad, from: coordinator)
        XCTAssertNotNil(textField.inputAccessoryView, "a number pad has no other way back")

        Field.applyAccessory(to: textField, keyboardType: .emailAddress, from: coordinator)
        XCTAssertNil(textField.inputAccessoryView, "a keyboard with a return key needs no bar")
    }

    /// Reassigning it while the field is first responder makes UIKit rebuild the
    /// input views under whoever is typing, so the same field keeps the same bar.
    func testAFieldKeepsTheBarItAlreadyCarries() {
        let textField = UITextField()
        let coordinator = numberPadField().makeCoordinator()

        Field.applyAccessory(to: textField, keyboardType: .numberPad, from: coordinator)
        let first = textField.inputAccessoryView
        Field.applyAccessory(to: textField, keyboardType: .numberPad, from: coordinator)

        XCTAssertTrue(first === textField.inputAccessoryView)
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

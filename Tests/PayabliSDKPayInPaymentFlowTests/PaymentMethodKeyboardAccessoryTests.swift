@testable import PayabliSDKPayInPaymentFlow
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
}

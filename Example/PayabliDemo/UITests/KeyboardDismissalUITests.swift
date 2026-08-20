import XCTest

/// Whether a payer can get out of the keyboard the SDK's form raises, driven
/// through the form the sample shows.
///
/// Neither test submits, so they need a reachable token server and nothing else.
///
/// The two keyboards divide the fields: one carries a return key, and one is a
/// number pad with the SDK's accessory bar. The return key can be asserted, since
/// pressing it is a key event and the keyboard's presence is observable. The bar
/// cannot: an input accessory's contents never enter the accessibility tree, which
/// a driven field confirmed. So the bar is captured as a screenshot and looked at,
/// on a device, which is also the only place its layout is real.
final class KeyboardDismissalUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-PayabliEnvironment", "qa"]
        app.launch()
        openTheSaveForm()
    }

    /// A `UITextField` keeps first responder when Return is pressed unless its
    /// delegate gives it up, so this is the fields that carry no accessory.
    func testReturnDismissesTheKeyboardOnAFieldThatHasOne() {
        let name = app.textFields["payabli.payInPaymentFlow.field.cardholderName"]
        XCTAssertTrue(name.waitForExistence(timeout: 10), "the cardholder field never appeared")
        name.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "no keyboard was raised")

        name.typeText("Ada\n")

        XCTAssertTrue(
            app.keyboards.firstMatch.waitForNonExistence(timeout: 5),
            "Return left the keyboard up, so this field has no way back"
        )
    }

    /// Attached rather than asserted: what a number pad looks like with the
    /// accessory attached is a rendering question, and this is the answer to it.
    func testWhatTheNumberPadShows() {
        let cardNumber = app.textFields["payabli.payInPaymentFlow.field.cardNumber"]
        XCTAssertTrue(cardNumber.waitForExistence(timeout: 10), "the card number field never appeared")
        cardNumber.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 10), "no keyboard was raised")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "number-pad-with-accessory"
        shot.lifetime = .keepAlways
        add(shot)
    }

    private func openTheSaveForm() {
        app.tabBars.buttons["Save"].tap()
        app.buttons["Check token endpoint"].tap()
        XCTAssertTrue(
            app.buttons["Check token endpoint"].waitForNonExistence(timeout: 30),
            "the token step never finished, so the form never appeared"
        )
    }
}

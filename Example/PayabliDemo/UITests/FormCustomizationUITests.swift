import XCTest

/// The S-Capture tab, walked through its presets. Nothing is submitted, so no token server is needed.
///
/// Each preset is attached as a screenshot, because what it changes is how the form looks.
final class FormCustomizationUITests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    func testTheTabIsAbsentUntilSwitchedOn() {
        let app = launch(showingSimpleCapture: false)

        XCTAssertTrue(app.tabBars.buttons["Config"].waitForExistence(timeout: 10))
        XCTAssertFalse(app.tabBars.buttons["S-Capture"].exists)
    }

    func testEachPresetRenders() {
        let app = launch(showingSimpleCapture: true)
        let tab = app.tabBars.buttons["S-Capture"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "the S-Capture tab is not shown")
        tab.tap()

        let cardNumber = app.textFields["payabli.payInPaymentFlow.field.cardNumber"]
        XCTAssertTrue(cardNumber.waitForExistence(timeout: 10), "the form never appeared")
        attachScreenshot("default-capture")

        choosePreset("Brand", in: app)
        attachScreenshot("brand-capture")

        choosePreset("Minimal", in: app)
        XCTAssertFalse(app.buttons["ACH"].exists, "the card-only preset still offers a bank account")
        attachScreenshot("minimal-capture")

        choosePreset("Brand", in: app)
        app.buttons["Tokenize"].tap()
        XCTAssertTrue(cardNumber.waitForExistence(timeout: 10))
        attachScreenshot("brand-tokenize")
    }

    private func launch(showingSimpleCapture: Bool) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["-PayabliEnvironment", "qa", "-showsSimpleCapture", showingSimpleCapture ? "YES" : "NO"]
        app.launch()
        return app
    }

    private func choosePreset(_ name: String, in app: XCUIApplication) {
        app.buttons["simpleCapture.menu"].tap()
        let item = app.buttons[name]
        XCTAssertTrue(item.waitForExistence(timeout: 5), "the \(name) preset is not in the menu")
        item.tap()
    }

    private func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}

/// The S-Capture tab submitting for real, once per operation, under the Brand preset.
///
/// Skips unless `PAYABLI_QA_LIVE` is `1`, because these charge a paypoint. Takes `PAYABLI_QA_ENVIRONMENT`
/// and `PAYABLI_QA_TOKEN_HOST` the same way the walkthrough does.
final class FormCustomizationLiveUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PAYABLI_QA_LIVE"] == "1",
            "set TEST_RUNNER_PAYABLI_QA_LIVE=1 to submit against a real paypoint"
        )
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        app.launchArguments = [
            "-PayabliEnvironment", environment["PAYABLI_QA_ENVIRONMENT"] ?? "qa",
            "-showsSimpleCapture", "YES"
        ]
        if let tokenHost = environment["PAYABLI_QA_TOKEN_HOST"], !tokenHost.isEmpty {
            app.launchArguments += ["-PayabliTokenHost", tokenHost]
        }
        app.launch()

        let tab = app.tabBars.buttons["S-Capture"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "the S-Capture tab is not shown")
        tab.tap()
        app.buttons["simpleCapture.menu"].tap()
        app.buttons["Brand"].tap()
    }

    func testCapturingUnderTheBrandPreset() {
        fillAndSubmit("Pay now")
        expectResult(prefix: "Captured:")
    }

    func testTokenizingUnderTheBrandPreset() {
        app.buttons["Tokenize"].tap()
        fillAndSubmit("Save securely")
        expectResult(prefix: "Saved:")
    }

    private func fillAndSubmit(_ submit: String) {
        let entries: [(String, String)] = [
            ("firstName", "Simple"),
            ("lastName", "Capture"),
            ("customerNumber", "SIMPLE-CAPTURE-IOS"),
            ("billingEmail", "simple-capture@example.com"),
            ("cardholderName", "Simple Capture"),
            ("cardNumber", "4242424242424242"),
            ("cardCvv", "999"),
            ("cardZip", "22039")
        ]
        for (field, text) in entries {
            let identifier = "payabli.payInPaymentFlow.field.\(field)"
            // The CVV is a secure field, so it is not among the text fields.
            let box = field == "cardCvv" ? app.secureTextFields[identifier] : app.textFields[identifier]
            XCTAssertTrue(box.waitForExistence(timeout: 10), "the form has no \(field) box")
            box.tap()
            box.typeText(text)
        }

        // The wheel opens on a future month, so accepting it is the whole choice.
        app.buttons["payabli.payInPaymentFlow.field.cardExpiration"].tap()
        let done = app.buttons["payabli.payInPaymentFlow.control.expirationDone"]
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the expiry picker never opened")
        done.tap()

        let button = app.buttons[submit]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "no \(submit) button")
        if !button.isHittable {
            app.swipeUp()
        }
        button.tap()
    }

    private func expectResult(prefix: String) {
        let outcome = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", prefix)).firstMatch
        let failure = app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH %@", "Failed:")).firstMatch
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline, !outcome.exists, !failure.exists {
            _ = outcome.waitForExistence(timeout: 1)
        }
        XCTAssertFalse(failure.exists, failure.exists ? failure.label : "")
        XCTAssertTrue(outcome.exists, "no \(prefix) result within thirty seconds")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = prefix
        shot.lifetime = .keepAlways
        add(shot)
    }
}

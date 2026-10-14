import XCTest

/// What the form shows the payer when a submission fails: the message for the failure's category, at the placement
/// the form was given, and never the failure's own text. Each state is attached as a screenshot.
///
/// The token-provider failure needs no server and no paypoint, because the token request never connects.
final class PayerFacingFailureUITests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    func testATokenProviderFailureShowsTheDefaultMessageAboveTheSubmitButton() {
        // Nothing listens on the discard port, so the provider's request is refused on the device itself.
        let form = FailingForm(test: self, tokenHost: "http://127.0.0.1:9")
        form.fill(cardNumber: "4242424242424242", holder: "Payer Facing")
        form.submit("Pay")

        form.expectMessage("The payment couldn't be completed.", placement: .aboveSubmitButton, submit: "Pay")
        form.attachScreenshot("token-provider-failure")
    }
}

/// The failures only a real paypoint produces, through the same form.
///
/// Skips unless `PAYABLI_QA_LIVE` is `1`, and takes `PAYABLI_QA_ENVIRONMENT` and `PAYABLI_QA_TOKEN_HOST` as the
/// walkthrough does. Which card declines is per paypoint; `5555…4444` declines on the sandbox one.
final class PayerFacingFailureLiveUITests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PAYABLI_QA_LIVE"] == "1",
            "set TEST_RUNNER_PAYABLI_QA_LIVE=1 to submit against a real paypoint"
        )
        continueAfterFailure = false
    }

    func testADeclineShowsTheDeclinedMessageAboveTheSubmitButton() {
        let form = openForm()
        form.fill(cardNumber: declined, holder: "Payer Facing")
        form.submit("Pay")

        form.expectMessage(declinedMessage, placement: .aboveSubmitButton, submit: "Pay")
        form.attachScreenshot("decline-above-submit")
    }

    func testADeclineShowsTheDeclinedMessageAtTheTopUnderTheBrandPreset() {
        let form = openForm()
        form.choosePreset("Brand")
        form.fill(cardNumber: declined, holder: "Payer Facing", customer: true)
        form.submit("Pay now")

        form.expectMessage(declinedMessage, placement: .top, submit: "Pay now")
        form.attachScreenshot("decline-top")
    }

    func testARefusedFieldIsMarkedAndNoMessageIsShown() {
        let form = openForm()
        // A card-number-shaped name is refused by the service and named as the field it was entered in.
        form.fill(cardNumber: "4242424242424242", holder: "4111111111111111")
        form.submit("Pay")

        form.expectMarkWithoutMessage(on: "Name on card")
        form.attachScreenshot("field-refusal")
    }

    private func openForm() -> FailingForm {
        let environment = ProcessInfo.processInfo.environment
        return FailingForm(
            test: self,
            environment: environment["PAYABLI_QA_ENVIRONMENT"] ?? "sandbox",
            tokenHost: environment["PAYABLI_QA_TOKEN_HOST"].flatMap { $0.isEmpty ? nil : $0 }
        )
    }

    private let declined = "5555555555554444"
    private let declinedMessage = "The payment was declined. Try another payment method."
}

/// The S-Capture form, driven far enough to fail, and read back.
private struct FailingForm {
    enum Placement {
        case top
        case aboveSubmitButton
    }

    let test: XCTestCase
    let app = XCUIApplication()

    init(test: XCTestCase, environment: String = "sandbox", tokenHost: String?) {
        self.test = test
        app.launchArguments = ["-PayabliEnvironment", environment, "-showsSimpleCapture", "YES"]
        if let tokenHost {
            app.launchArguments += ["-PayabliTokenHost", tokenHost]
        }
        app.launch()

        let tab = app.tabBars.buttons["S-Capture"]
        XCTAssertTrue(tab.waitForExistence(timeout: composes), "the S-Capture tab is not shown")
        tab.tap()
        XCTAssertTrue(field("cardNumber").waitForExistence(timeout: composes), "the form never appeared")
    }

    func choosePreset(_ name: String) {
        app.buttons["simpleCapture.menu"].tap()
        let item = app.buttons[name]
        XCTAssertTrue(item.waitForExistence(timeout: composes), "the \(name) preset is not in the menu")
        item.tap()
    }

    /// Fills every box the card form draws, and the customer section's when the preset draws one.
    func fill(cardNumber: String, holder: String, customer: Bool = false) {
        var entries: [(String, String)] = [
            ("cardholderName", holder),
            ("cardNumber", cardNumber),
            ("cardCvv", "999"),
            ("cardZip", "22039")
        ]
        if customer {
            entries = [
                ("firstName", "Payer"),
                ("lastName", "Facing"),
                ("customerNumber", "PAYER-FACING-IOS"),
                ("billingEmail", "payer-facing@example.com")
            ] + entries
        }
        for (name, text) in entries {
            let box = field(name)
            XCTAssertTrue(box.waitForExistence(timeout: composes), "the form has no \(name) box")
            scrollTo(box)
            box.tap()
            box.typeText(text)
        }

        // The wheel opens on the current month, which is still a valid expiry, so accepting it is the whole choice.
        let expiry = app.buttons["payabli.payIn.field.cardExpiration"]
        scrollTo(expiry)
        expiry.tap()
        let done = app.buttons["payabli.payIn.control.expirationDone"]
        XCTAssertTrue(done.waitForExistence(timeout: composes), "the expiry picker never opened")
        done.tap()
    }

    func submit(_ label: String) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: composes), "no \(label) button")
        scrollTo(button)
        button.tap()
    }

    /// The form-level message reads exactly `text`, once, at `placement`, and no field is marked.
    func expectMessage(_ text: String, placement: Placement, submit: String) {
        let message = formMessage
        XCTAssertTrue(
            message.waitForExistence(timeout: answers),
            "no form-level message within \(Int(answers))s. On screen: \(onScreen)"
        )
        XCTAssertEqual(message.value as? String, text, "the form shows something other than its category's message")
        XCTAssertEqual(formMessages.count, 1, "the form draws more than one message")
        XCTAssertFalse(fieldMark.exists, "a failure that names no field marked one")

        let first = field("cardNumber").frame
        switch placement {
        case .top:
            XCTAssertLessThan(message.frame.maxY, first.minY, "the message is not above the fields")
        case .aboveSubmitButton:
            XCTAssertGreaterThan(message.frame.minY, first.maxY, "the message is not below the fields")
            XCTAssertLessThanOrEqual(
                message.frame.maxY,
                app.buttons[submit].frame.minY,
                "the message is not above the submit button"
            )
        }

        // Both bars float over the form and either can cover the message, so it is dragged into the band between them
        // for the screenshot to show it. Short drags, because a swipe's momentum carries it past.
        let top = app.navigationBars.firstMatch.frame.maxY
        let tabBar = app.tabBars.firstMatch
        let bottom = tabBar.exists ? tabBar.frame.minY : app.windows.firstMatch.frame.maxY
        let center = app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        var drags = 0
        while message.frame.minY < top || message.frame.maxY > bottom, drags < scrolls * 3 {
            let towards: CGFloat = message.frame.minY < top ? 0.15 : -0.15
            center.press(
                forDuration: 0.05,
                thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5 + towards))
            )
            drags += 1
        }
    }

    /// The field labelled `label` carries the refusal's mark, and the form draws no message of its own.
    func expectMarkWithoutMessage(on label: String) {
        let mark = fieldMark
        XCTAssertTrue(
            mark.waitForExistence(timeout: answers),
            "no field was marked within \(Int(answers))s. On screen: \(onScreen)"
        )
        XCTAssertEqual(mark.label, "\(label) error", "the refusal marked a field other than the one it named")
        XCTAssertFalse(formMessage.exists, "a refusal that marks a field also drew a message")
    }

    func attachScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        test.add(shot)
    }

    // MARK: - Reading the form

    private var formMessages: XCUIElementQuery {
        app.staticTexts.matching(NSPredicate(format: "label == %@", "Payment error"))
    }

    private var formMessage: XCUIElement {
        formMessages.firstMatch
    }

    private var fieldMark: XCUIElement {
        app.staticTexts.matching(NSPredicate(format: "value == %@", "That was not accepted")).firstMatch
    }

    /// What a failure names when it is not the one expected, so the report says what the screen said.
    private var onScreen: String {
        app.staticTexts.allElementsBoundByIndex.map(\.label).joined(separator: " | ")
    }

    private func field(_ name: String) -> XCUIElement {
        let identifier = "payabli.payIn.field.\(name)"
        // The CVV is a secure field, so it is not among the text fields.
        return name == "cardCvv" ? app.secureTextFields[identifier] : app.textFields[identifier]
    }

    private func scrollTo(_ element: XCUIElement) {
        var swipes = 0
        while !element.isHittable, swipes < scrolls {
            app.swipeUp()
            swipes += 1
        }
    }

    /// A real request over a real link.
    private let answers: TimeInterval = 30

    /// No network in it: a control on its way to the screen.
    private let composes: TimeInterval = 10

    /// Enough to cross the Brand form, which is the longest.
    private let scrolls = 6
}

import XCTest

/// The four card-not-present flows, driven through the form the sample actually shows, against a real environment.
///
/// These submit, so they need a reachable token server and a configured paypoint, and they send real requests.
/// Android's counterpart is `QaWalkthroughTest` in `sdk-android`, gated the same way and asserting the same four
/// outcomes; the point of driving the UI rather than the SDK is that several devices run it at once and each
/// screen shows what it is doing.
///
/// What makes the resulting rows attributable is the prefill: it fills the form from `QAIdentity`, so no two
/// devices submit the same customer.
///
/// Every test skips unless `PAYABLI_QA_LIVE` is `1`, so opening the scheme and pressing run charges nothing.
///
/// ```
/// TEST_RUNNER_PAYABLI_QA_LIVE=1 \
/// xcodebuild test -project Example/PayabliDemo/PayabliDemo.xcodeproj -scheme 'PayabliDemo qa' \
///   -only-testing:PayabliDemoUITests -destination 'id=<simulator udid>'
/// ```
///
/// The token server has to be up on 8787, which a simulator reaches at `127.0.0.1` with nothing configured.
///
/// `PAYABLI_QA_ENVIRONMENT` reaches the runner only through the `TEST_RUNNER_` prefix, which `xcodebuild`
/// strips: `TEST_RUNNER_PAYABLI_QA_ENVIRONMENT=sandbox xcodebuild test ...`. Set plainly it reaches
/// `xcodebuild` and stops there, which looks exactly like a variable that had no effect.
final class QAWalkthroughUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        try super.setUpWithError()

        // These submit real payments, so a run is opted into rather than assumed.
        // Without this an operator opening the scheme and pressing run charges a
        // paypoint. The sibling platform excludes its walkthrough the same way.
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["PAYABLI_QA_LIVE"] == "1",
            "set TEST_RUNNER_PAYABLI_QA_LIVE=1 to submit against a real paypoint"
        )

        continueAfterFailure = false
        app = XCUIApplication()
        // The environment is remembered, so it is passed every launch rather than relied on from the last one.
        app.launchArguments = ["-PayabliEnvironment", environment]
        app.launch()
    }

    func testSavingACardThePayerEntered() {
        openTheForm(tab: "Save", submit: save)

        prefill(customerNumber: true)
        chooseAnExpiry()
        submit(save)

        expectOutcome("Added a new payment method.", failurePrefix: methodFailure)
    }

    func testSavingABankAccountThePayerEntered() {
        openTheForm(tab: "Save", submit: save)

        chooseTheBankAccount()
        prefill(customerNumber: true)
        submit(save)

        expectOutcome("Added a new payment method.", failurePrefix: methodFailure)
    }

    func testCapturingACardThePayerEntered() {
        openTheForm(tab: "Capture", submit: capture)

        // The figure the request carries, under a form whose own summary reads back an amount and a fee and
        // never their sum. A payer sees what leaves the account or the screen is lying by omission.
        XCTAssertTrue(app.staticTexts["Total"].waitForExistence(timeout: composes), "the total is not on screen")

        prefill()
        chooseAnExpiry()
        submit(capture)

        expectOutcome("Payment submitted", failurePrefix: captureFailure)
    }

    func testCapturingABankAccountThePayerEntered() {
        openTheForm(tab: "Capture", submit: capture)

        chooseTheBankAccount()
        prefill()
        submit(capture)

        expectOutcome("Payment submitted", failurePrefix: captureFailure)
    }

    // MARK: - The walk

    /// Up to the form, which is the second step and stays blocked until the token endpoint has answered.
    private func openTheForm(tab: String, submit: String) {
        // A launch is not an appearance, so each control is waited for rather
        // than tapped at whatever is on screen when the walk reaches it.
        tap(app.tabBars.buttons[tab], named: "the \(tab) tab")
        tap(app.buttons["Check token endpoint"], named: "the token endpoint button")

        // The button's absence, not the submit button and not the answer text: the
        // form is on screen from launch, so its button exists before anything has
        // been fetched, and a step that finishes hides its own content, so the ✓
        // the probe writes leaves with the button that asked for it. A refusal
        // keeps both, which is what the failure below reads.
        if !app.buttons["Check token endpoint"].waitForNonExistence(timeout: answers) {
            let refusal = app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH %@", "✗")
            ).firstMatch
            XCTFail(refusal.exists
                ? refusal.label
                : "the token endpoint neither answered nor refused. Is the server up on 8787?")
        }
        XCTAssertTrue(
            app.buttons[submit].waitForExistence(timeout: composes),
            "the form has no \(submit) button"
        )
    }

    /// Waits for an element to be there and to accept a tap, and says which one
    /// it was when it never arrives.
    private func tap(_ element: XCUIElement, named name: String) {
        // Nothing tapped in the walk waits on a request: the two that do are the
        // token step and the outcome, and both wait for themselves.
        XCTAssertTrue(element.waitForExistence(timeout: composes), "\(name) never appeared")

        // The form is taller than the screen, so it holds its own submit button
        // below the fold, and an element off screen is never hittable. Existing is
        // therefore not enough to tap: the page is brought to the control.
        var swipes = 0
        while !element.isHittable, swipes < scrolls {
            app.swipeUp()
            swipes += 1
        }

        // Hittability is waited for, not asserted once: an element exists before it
        // settles, so a single check reads whatever the animation was doing.
        let hittable = expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: element)
        XCTAssertEqual(
            XCTWaiter.wait(for: [hittable], timeout: composes),
            .completed,
            "\(name) appeared but never became tappable"
        )
        element.tap()
    }

    /// The instrument the form is on, which the prefill then fills.
    ///
    /// Waited for by a bank-only field, because the prefill fills the boxes that are mounted and the swap takes
    /// a frame. Prefilled too early it fills the card boxes it can still see, the bank ones stay empty, and the
    /// form refuses itself. Measured on Android, where three of four devices lost that race.
    private func chooseTheBankAccount() {
        tap(app.buttons["ACH"], named: "the bank-account option")
        let routing = app.textFields["payabli.payInPaymentFlow.field.achRouting"]
        XCTAssertTrue(routing.waitForExistence(timeout: composes), "the form never switched to the bank account")
    }

    /// - Parameter customerNumber: whether the form carries that box. The save form
    ///   collects it and a capture names its customer through the request, so the
    ///   two flows expect different fields filled.
    private func prefill(customerNumber: Bool = false) {
        tap(app.buttons["Prefill test data (Debug)"], named: "the prefill button")

        // That the fields naming the payer were filled, which is what makes the row this produces
        // attributable. Not *what* they were filled with: a field's accessibility value is "Entered" or
        // "Empty", never its text, so a card number cannot be read back out of the form. Which values the
        // identity produces is covered by `QAIdentityTests`.
        for field in ["lastName", "billingEmail"] + (customerNumber ? ["customerNumber"] : []) {
            let box = app.textFields["payabli.payInPaymentFlow.field.\(field)"]
            XCTAssertTrue(box.waitForExistence(timeout: composes), "the form has no \(field) box")
            XCTAssertEqual(box.value as? String, "Entered", "the prefill left \(field) empty")
        }
    }

    /// The expiry is a wheel the prefill cannot reach, so it is opened and accepted.
    ///
    /// The field preselects a valid month when it opens, so accepting is the whole interaction. ACH has no
    /// expiry, which is why this is a step of the card flows only.
    private func chooseAnExpiry() {
        tap(app.buttons["payabli.payInPaymentFlow.field.cardExpiration"], named: "the expiry field")
        tap(
            app.buttons["payabli.payInPaymentFlow.control.expirationDone"],
            named: "the expiry picker's Done button"
        )
    }

    private func submit(_ button: String) {
        tap(app.buttons[button], named: "the \(button) button")
    }

    /// Waits for the outcome and, if it is a refusal, fails naming what the screen said.
    ///
    /// Without this the failure is a bare "element did not appear", which is the same message for a declined
    /// payment, an unreachable service and a button that moved. The screen already renders the reason.
    private func expectOutcome(_ success: String, failurePrefix: String) {
        let succeeded = app.staticTexts[success]
        let refused = app.staticTexts.matching(
            NSPredicate(format: "label BEGINSWITH %@", failurePrefix)
        )

        let deadline = Date().addingTimeInterval(answers)
        while Date() < deadline {
            if succeeded.exists {
                return
            }
            let refusal = refused.firstMatch
            if refusal.exists {
                XCTFail("the service refused it: \(refusal.label)")
                return
            }
            _ = succeeded.waitForExistence(timeout: 1)
        }

        XCTFail("nothing came back within \(Int(answers))s: neither \"\(success)\" nor a reason")
    }

    // MARK: - What the run is pointed at

    /// Overridable so one build can be walked against either paypoint, since the entry point follows the
    /// environment and neither is compiled into the request.
    private var environment: String {
        ProcessInfo.processInfo.environment["PAYABLI_QA_ENVIRONMENT"] ?? "qa"
    }

    private let save = "Add Payment Method"
    private let capture = "Submit Payment"
    private let methodFailure = "Payment method failed:"
    private let captureFailure = "Payment capture failed:"

    /// A real request over a real link, so this is a network timeout rather than a composition one.
    private let answers: TimeInterval = 30

    /// No network in it: a control on its way to the screen, or form state the next frame draws.
    private let composes: TimeInterval = 5

    /// Enough to cross the longest form the walk meets, which is ACH with a customer number.
    private let scrolls = 6
}

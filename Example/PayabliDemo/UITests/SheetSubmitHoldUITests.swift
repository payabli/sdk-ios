import XCTest

/// The payment sheet's Back button, pressed with nothing in flight and again while a save is in flight.
///
/// A save is in flight for about a second, too short to press anything in. So the run names a token host that holds
/// the SDK's token request, `held_token_proxy.py` beside this file, and the save waits on it.
final class SheetSubmitHoldUITests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        guard let heldHost = ProcessInfo.processInfo.environment["PAYABLI_QA_HELD_TOKEN_HOST"], !heldHost.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_PAYABLI_QA_HELD_TOKEN_HOST to a running held_token_proxy.py")
        }
        continueAfterFailure = false
        app.launchArguments = ["-PayabliEnvironment", "sandbox", "-PayabliTokenHost", heldHost]
        app.launch()
    }

    func testTheBackButtonIsRefusedWhileASaveIsInFlight() {
        tap(app.tabBars.buttons["Save"])
        tap(app.buttons["Check token endpoint"])
        XCTAssertTrue(app.buttons["Check token endpoint"].waitForNonExistence(timeout: 30), "the token check never ended")

        let back = app.buttons["Back"]
        tap(app.buttons["Open as a sheet instead"])
        tap(back)
        XCTAssertTrue(back.waitForNonExistence(timeout: 5), "Back doesn't close the sheet with nothing in flight")

        tap(app.buttons["Open as a sheet instead"])
        XCTAssertTrue(back.waitForExistence(timeout: 5), "the sheet never opened again")
        tap(hittable(app.buttons.matching(identifier: "payabli.payIn.field.cardExpiration")))
        tap(hittable(app.buttons.matching(identifier: "payabli.payIn.control.expirationDone")))
        tap(hittable(app.buttons.matching(NSPredicate(format: "label == %@", "Save payment method"))))
        back.tap()
        XCTAssertFalse(back.waitForNonExistence(timeout: 3), "Back closed the sheet while the save was in flight")
    }

    private func hittable(_ query: XCUIElementQuery) -> XCUIElement {
        let deadline = Date().addingTimeInterval(5)
        repeat {
            if let match = query.allElementsBoundByIndex.first(where: { $0.exists && $0.isHittable }) {
                return match
            }
            app.swipeUp()
        } while Date() < deadline
        return query.firstMatch
    }

    private func tap(_ element: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 10), "\(element) never appeared")
        element.tap()
    }
}

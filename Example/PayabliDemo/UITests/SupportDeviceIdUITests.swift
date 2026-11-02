import XCTest

/// The Config tab's device ID, the value support asks for. Nothing is submitted, so no token server is needed.
///
/// What a copy puts on the pasteboard is not read here: the runner is refused the app's pasteboard.
final class SupportDeviceIdUITests: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    func testTheConfigTabShowsTheDeviceIdWithACopyAction() {
        let app = XCUIApplication()
        app.launchArguments = ["-PayabliEnvironment", "sandbox"]
        app.launch()

        let tab = app.tabBars.buttons["Config"]
        XCTAssertTrue(tab.waitForExistence(timeout: 10), "the Config tab is not shown")
        tab.tap()

        XCTAssertTrue(app.staticTexts["Device ID"].waitForExistence(timeout: 5), "the Device ID row is not shown")
        XCTAssertFalse(app.staticTexts["Unavailable"].exists, "the session answered no device ID")
        let id = NSPredicate(format: "label MATCHES %@", "^[0-9a-f]{32}$")
        XCTAssertTrue(app.staticTexts.matching(id).firstMatch.waitForExistence(timeout: 5), "no device ID is on screen")
        XCTAssertTrue(app.buttons["Copy Device ID"].isHittable, "the Device ID row offers no copy")

        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = "config-support-device-id"
        shot.lifetime = .keepAlways
        add(shot)
    }
}

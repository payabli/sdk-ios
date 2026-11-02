import XCTest

/// The line a failed action leaves on the Tap to Pay tab.
final class ActionLineTests: XCTestCase {
    private struct Refusal: LocalizedError {
        var errorDescription: String? {
            "The merchant declined the terms."
        }
    }

    func testAFailureIsTheMarkPlusTheErrorsMessage() {
        XCTAssertEqual(ActionLine.failed(Refusal()), "✗ The merchant declined the terms.")
    }
}

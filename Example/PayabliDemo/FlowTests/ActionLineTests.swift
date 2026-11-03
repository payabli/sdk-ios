import PayabliSDKCore
import XCTest

/// The line a failed action leaves on the Tap to Pay tab.
final class ActionLineTests: XCTestCase {
    private struct Refusal: PayabliError {
        var type: PayabliErrorType {
            .paymentDeclined
        }

        var reason: String {
            "The merchant declined the terms."
        }

        var detail: String? {
            nil
        }
    }

    private struct Shown: DisplayedFailure {
        let message = "This iPhone can't do that."
    }

    func testAFailureIsTheMarkPlusItsCategorysMessageAndNeverItsOwnText() {
        XCTAssertEqual(ActionLine.failed(Refusal()), "✗ The payment was declined.")
    }

    func testAFailureThatAlreadyCarriesItsMessageKeepsIt() {
        XCTAssertEqual(ActionLine.failed(Shown()), "✗ This iPhone can't do that.")
        XCTAssertEqual(ActionLine.message(for: Shown()), "This iPhone can't do that.")
    }
}

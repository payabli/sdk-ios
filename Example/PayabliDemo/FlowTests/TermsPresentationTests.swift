import PayabliSDKCore
import XCTest

/// The line the Tap to Pay tab shows after asking the SDK to present the terms.
final class TermsPresentationTests: XCTestCase {
    private struct Refusal: PayabliError {
        var type: PayabliErrorType {
            .readerUnavailable
        }

        var reason: String {
            "The reader is not ready."
        }

        var detail: String? {
            nil
        }
    }

    func testAFailedPresentationIsTheMarkPlusItsCategorysMessageWithNoStepName() {
        XCTAssertEqual(TermsPresentation.failed(Refusal()).line, "✗ That didn't work. Please try again.")
    }

    func testAReturnedPresentationReportsWhatAskingFound() {
        XCTAssertEqual(TermsPresentation.returned(accepted: .success(true)).line, "returned; now ✓ Accepted")
        XCTAssertEqual(TermsPresentation.returned(accepted: .success(false)).line, "returned; still ✗ Not accepted")
    }

    func testAFailureToAskAfterwardsIsNotReportedAsAFailedPresentation() {
        XCTAssertEqual(
            TermsPresentation.returned(accepted: .failure(Refusal())).line,
            "returned; could not ask whether accepted: That didn't work. Please try again."
        )
    }
}

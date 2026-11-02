import XCTest

/// The line the Tap to Pay tab shows after asking the SDK to present the terms.
final class TermsPresentationTests: XCTestCase {
    private struct Refusal: LocalizedError {
        var errorDescription: String? {
            "The reader is not ready."
        }
    }

    func testAFailedPresentationIsTheMarkPlusTheErrorsMessageWithNoStepName() {
        XCTAssertEqual(TermsPresentation.failed(Refusal()).line, "✗ The reader is not ready.")
    }

    func testAReturnedPresentationReportsWhatAskingFound() {
        XCTAssertEqual(TermsPresentation.returned(accepted: .success(true)).line, "returned; now ✓ Accepted")
        XCTAssertEqual(TermsPresentation.returned(accepted: .success(false)).line, "returned; still ✗ Not accepted")
    }

    func testAFailureToAskAfterwardsIsNotReportedAsAFailedPresentation() {
        XCTAssertEqual(
            TermsPresentation.returned(accepted: .failure(Refusal())).line,
            "returned; could not ask whether accepted: The reader is not ready."
        )
    }
}

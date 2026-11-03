import PayabliSDKPayIn
import XCTest

/// What a success screen shows: the result's code and identifiers, never the service's text.
final class PayInOutcomeRowsTests: XCTestCase {
    func testAStoredMethodShowsItsCodeAndIdAndNothingElse() {
        let stored = PayabliPayInStoredMethod(
            storedMethodId: "stored-123",
            method: .card,
            methodReferenceId: "method-123",
            customerId: 4440
        )

        let outcome = PayInOutcome(.method(stored))

        XCTAssertEqual(outcome.summaryRows.map(\.label), ["Code", "Stored method ID"])
        XCTAssertEqual(outcome.summaryRows.map(\.value), ["1", "stored-123"])
        XCTAssertEqual(outcome.headline, "Code 1")
    }
}

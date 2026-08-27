import PayabliSDKCore
import PayabliSDKPayInPaymentFlow
import XCTest

/// How a failure reads on each of the two flows.
///
/// One adapter builds both screens' failures, and a 409 means different things on
/// them. A capture sends an idempotency key, so a conflict says the service
/// answered from an attempt that already reached it and the next submit repeats it.
/// A stored method sends no key and offers no new attempt, so the same status is
/// just what the service said.
///
/// Both shapes a conflict arrives in are covered: the typed failure carries the
/// status where the API answered with a body, and an empty one reaches the mapper
/// with no 409 case and comes back as the bare reason.
final class PayInFailureTests: XCTestCase {
    func testATypedConflictOnACaptureNamesTheKey() {
        let failure = PayInFailure(typedConflict, operation: .capture)

        XCTAssertTrue(failure.isDuplicateSubmission)
        XCTAssertTrue(failure.message.contains("idempotency key"), failure.message)
    }

    func testABareConflictOnACaptureNamesTheKey() {
        let failure = PayInFailure(BareReason(reason: "HTTP 409"), operation: .capture)

        XCTAssertTrue(failure.isDuplicateSubmission)
        XCTAssertTrue(failure.message.contains("idempotency key"), failure.message)
    }

    func testATypedConflictOnAStoredMethodSaysWhatTheServiceSaid() {
        let failure = PayInFailure(typedConflict, operation: .storedMethod)

        XCTAssertFalse(failure.isDuplicateSubmission)
        XCTAssertFalse(failure.message.contains("idempotency key"), failure.message)
    }

    func testABareConflictOnAStoredMethodSaysWhatTheServiceSaid() {
        let failure = PayInFailure(BareReason(reason: "HTTP 409"), operation: .storedMethod)

        XCTAssertFalse(failure.isDuplicateSubmission)
        XCTAssertEqual(failure.message, "HTTP 409")
    }

    /// A validation failure's reason is the server's own title, which can carry
    /// those three digits for its own reasons, so the match is the exact string.
    func testAReasonThatMerelyMentions409IsNotAConflict() {
        let failure = PayInFailure(
            BareReason(reason: "Rejected: field 409 is not a valid account"),
            operation: .capture
        )

        XCTAssertFalse(failure.isDuplicateSubmission)
        XCTAssertFalse(failure.message.contains("idempotency key"), failure.message)
    }

    func testAFailureThatIsNotAConflictReadsAsItself() {
        let failure = PayInFailure(
            PayabliPayInPaymentFlowError.transactionFailed(
                PayabliPayInPaymentFlowFailure(reason: "Declined", httpStatusCode: 402)
            ),
            operation: .capture
        )

        XCTAssertFalse(failure.isDuplicateSubmission)
        XCTAssertFalse(failure.message.contains("idempotency key"), failure.message)
    }

    // MARK: -

    private var typedConflict: Error {
        PayabliPayInPaymentFlowError.transactionFailed(
            PayabliPayInPaymentFlowFailure(reason: "Conflict", httpStatusCode: 409)
        )
    }
}

/// A failure carrying only what the transport built for a status it does not map,
/// which is what an empty body becomes.
private struct BareReason: PayabliError {
    let reason: String
    var code: PayabliErrorCode {
        .unknown
    }

    var detail: String? {
        nil
    }
}

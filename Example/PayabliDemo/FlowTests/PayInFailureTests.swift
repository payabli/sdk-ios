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
/// status where the API answered with a body, and an empty one carries the code
/// the status mapping supplies.
final class PayInFailureTests: XCTestCase {
    func testATypedConflictOnACaptureNamesTheKey() {
        let failure = PayInFailure(typedConflict, operation: .capture)

        XCTAssertTrue(failure.isDuplicateSubmission)
        XCTAssertTrue(failure.message.contains("idempotency key"), failure.message)
    }

    func testABareConflictOnACaptureNamesTheKey() {
        let failure = PayInFailure(
            BareReason(reason: "Conflict (409)", code: .conflict),
            operation: .capture
        )

        XCTAssertTrue(failure.isDuplicateSubmission)
        XCTAssertTrue(failure.message.contains("idempotency key"), failure.message)
    }

    func testATypedConflictOnAStoredMethodSaysWhatTheServiceSaid() {
        let failure = PayInFailure(typedConflict, operation: .storedMethod)

        XCTAssertFalse(failure.isDuplicateSubmission)
        XCTAssertFalse(failure.message.contains("idempotency key"), failure.message)
    }

    func testABareConflictOnAStoredMethodSaysWhatTheServiceSaid() {
        let failure = PayInFailure(
            BareReason(reason: "Conflict (409)", code: .conflict),
            operation: .storedMethod
        )

        XCTAssertFalse(failure.isDuplicateSubmission)
        XCTAssertEqual(failure.message, "Conflict (409)")
    }

    /// A validation failure's reason is the server's own title, which can carry
    /// those three digits for its own reasons. The code decides, so the text is not
    /// read and cannot be mistaken for one.
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

    /// A validation failure's own description names each rejected field, which is
    /// the part saying what to correct. The title alone is usually "Validation
    /// failed", which tells a merchant nothing.
    func testAValidationFailureKeepsTheFieldsItRejected() throws {
        let json = Data(#"""
        {
          "title": "Validation failed",
          "detail": "one or more fields were rejected",
          "errors": { "cardNumber": [ { "message": "is not a valid card number" } ] }
        }
        """#.utf8)
        let validation = try JSONDecoder().decode(PayabliValidationError.self, from: json)

        let failure = PayInFailure(validation, operation: .storedMethod)

        XCTAssertTrue(failure.message.contains("cardNumber"), failure.message)
        XCTAssertTrue(failure.message.contains("is not a valid card number"), failure.message)
    }

    /// The same for a failure whose description carries an action.
    func testAFailureKeepsTheActionItNames() {
        let failure = PayInFailure(ActionableDecline(), operation: .storedMethod)

        XCTAssertTrue(failure.message.contains("Ask for another card"), failure.message)
    }

    // MARK: -

    private var typedConflict: Error {
        PayabliPayInPaymentFlowError.transactionFailed(
            PayabliPayInPaymentFlowFailure(reason: "Conflict", httpStatusCode: 409)
        )
    }
}

/// A failure whose own description carries more than its reason, which is what the
/// SDK's validation and decline types do.
private struct ActionableDecline: PayabliError {
    var reason: String {
        "Declined"
    }

    var code: PayabliErrorCode {
        .unknown
    }

    var detail: String? {
        nil
    }

    var errorDescription: String? {
        "Declined · Ask for another card"
    }
}

/// A failure carrying only what the transport built for a status it does not map,
/// which is what an empty body becomes.
private struct BareReason: PayabliError {
    let reason: String
    var code: PayabliErrorCode = .unknown

    var detail: String? {
        nil
    }
}

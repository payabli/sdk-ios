import PayabliSDKCore
import PayabliSDKPayInPaymentFlow
import XCTest

/// The transitions that decide whether a payment can be reversed twice.
///
/// The live walkthrough reaches the approved reversal and nothing else. Everything below is a branch
/// it never takes, and each one keeps an operator either from meeting a refusal they did nothing to
/// earn, or from losing the transaction they were told to read back.
final class PayInReversalStateTests: XCTestCase {
    private let payment = "32-abc"
    private let other = "32-def"

    // MARK: - A reversal that answered

    func testAReversedPaymentIsNotOfferedAgain() {
        var state = PayInReversalState()
        state.began()
        state.reversed(payment, saying: "Reversed", onScreen: payment)

        XCTAssertFalse(state.offersReversal(of: payment))
        XCTAssertFalse(state.isReversing)
        XCTAssertEqual(state.message, "Reversed")
    }

    func testAnAnswerForAPaymentNoLongerOnScreenIsNotShown() {
        var state = PayInReversalState()
        state.began()
        state.reversed(payment, saying: "Reversed", onScreen: other)

        XCTAssertEqual(state.message, "", "an answer was painted onto the payment that replaced it")
        XCTAssertFalse(state.offersReversal(of: payment), "and it still happened")
    }

    /// The property both guards lean on. The flow cannot report a submission until the call reaches
    /// it, which is a scheduled task later, so this is what refuses a second tap in between.
    func testAReversalIsInFlightFromTheMomentItIsDecidedOn() {
        var state = PayInReversalState()
        state.began()

        XCTAssertTrue(state.isReversing)
    }

    // MARK: - A reversal that never answered

    func testAnUnresolvedReversalIsNotOfferedAgain() {
        var state = PayInReversalState()
        state.began()
        state.failed(interrupted, for: payment, onScreen: payment)

        XCTAssertFalse(
            state.offersReversal(of: payment),
            "a reversal that may have applied was offered again, and the service refuses the repeat"
        )
        XCTAssertEqual(state.unreconciled, [payment])
    }

    func testAnUnresolvedReversalSurvivesTheNextPayment() {
        var state = PayInReversalState()
        state.began()
        state.failed(interrupted, for: payment, onScreen: payment)
        state.paymentReplaced()

        XCTAssertEqual(
            state.unreconciled,
            [payment],
            "the transaction to read back went with the payment that left the screen"
        )
        XCTAssertEqual(state.message, "", "and its message stayed behind on a payment that is gone")
    }

    func testASettledReversalDoesNotAnswerForAnUnresolvedOne() {
        var state = PayInReversalState()
        state.failed(interrupted, for: payment, onScreen: payment)
        state.failed(refused, for: other, onScreen: other)

        XCTAssertEqual(
            state.unreconciled,
            [payment],
            "one reversal's refusal answered another reversal's open question"
        )
    }

    func testTwoUnresolvedReversalsAreBothKept() {
        var state = PayInReversalState()
        state.failed(interrupted, for: payment, onScreen: payment)
        state.failed(interrupted, for: other, onScreen: other)

        XCTAssertEqual(state.unreconciled, [payment, other])
    }

    func testAnUnresolvedReversalIsClosedByOneThatAnswers() {
        var state = PayInReversalState()
        state.failed(interrupted, for: payment, onScreen: payment)
        state.reversed(payment, saying: "Reversed", onScreen: payment)

        XCTAssertEqual(state.unreconciled, [], "the question was answered and the notice stayed up")
    }

    // MARK: - A refusal that belongs to nobody

    func testARefusalForAnotherSubmissionChangesNothing() {
        var state = PayInReversalState()
        state.failed(interrupted, for: payment, onScreen: payment)
        let afterInterruption = state

        state.failed(refusedForAnotherSubmission, for: payment, onScreen: payment)

        XCTAssertEqual(
            state.unreconciled,
            afterInterruption.unreconciled,
            "a call that was never made cleared what an earlier one left open"
        )
        XCTAssertEqual(
            state.message,
            afterInterruption.message,
            "a call that was never made reported itself as this payment's answer"
        )
    }

    func testARefusalForAnotherSubmissionStillEndsTheAttempt() {
        var state = PayInReversalState()
        state.began()
        state.failed(refusedForAnotherSubmission, for: payment, onScreen: payment)

        XCTAssertFalse(state.isReversing, "the screen was left believing a reversal was still running")
    }

    // MARK: - A settled refusal

    func testARefusedReversalCanBeTriedAgain() {
        var state = PayInReversalState()
        state.failed(refused, for: payment, onScreen: payment)

        XCTAssertTrue(state.offersReversal(of: payment), "the service answered, so there is no doubt to hold")
        XCTAssertEqual(state.unreconciled, [])
    }

    // MARK: - Fixtures

    private var interrupted: PayInFailure {
        PayInFailure(
            PayabliPayInPaymentFlowError.submissionInterrupted(
                code: .networkError,
                causeType: "PayabliSDKCore.PayabliGenericError"
            ),
            operation: .void
        )
    }

    private var refused: PayInFailure {
        PayInFailure(
            PayabliPayInPaymentFlowError.transactionFailed(
                PayabliPayInPaymentFlowFailure(
                    code: "D0001",
                    reason: "Declined",
                    explanation: nil,
                    action: nil,
                    httpStatusCode: 402
                )
            ),
            operation: .void
        )
    }

    private var refusedForAnotherSubmission: PayInFailure {
        PayInFailure(PayabliPayInPaymentFlowError.submissionInProgress, operation: .void)
    }
}

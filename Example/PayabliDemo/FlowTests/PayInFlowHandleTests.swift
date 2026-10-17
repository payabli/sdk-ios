@testable import PayabliSDKCore
import PayabliSDKPayIn
import XCTest

/// Whether the next submit is a new payment or a retry of one whose outcome is unknown.
///
/// Idle only: nothing in this target can hold a submission open, so the refusal during one is not covered.
@MainActor
final class PayInFlowHandleTests: XCTestCase {
    func testDrawingAnAttemptIsANewPaymentUnderANewReference() throws {
        let handle = try makeHandle()

        XCTAssertTrue(handle.startNewAttempt(suppliesCustomer: true))
        let first = handle.requestReference
        XCTAssertTrue(handle.startNewAttempt(suppliesCustomer: true))

        XCTAssertEqual(handle.requestAttempt, .newPayment)
        XCTAssertNotNil(first, "the attempt names no payment")
        XCTAssertNotEqual(handle.requestReference, first, "a new payment reused the earlier reference")
        XCTAssertNotNil(handle.requestOrderId, "the attempt names no order")
        XCTAssertEqual(handle.requestTotal.map { $0 > 0 }, true, "the attempt charges nothing")
    }

    func testDrawingAnAttemptForwardsTheAmountAndSourceItIsGiven() throws {
        let handle = try makeHandle()

        XCTAssertTrue(handle.startNewAttempt(suppliesCustomer: false, amount: 12.34, source: "test-source"))

        XCTAssertEqual(handle.requestTotal, 12.34)
        XCTAssertEqual(handle.requestSource, "test-source")
    }

    func testAnUnknownOutcomeMakesTheNextSubmitARetryOfTheSameAttempt() throws {
        let handle = try makeHandle()
        XCTAssertTrue(handle.startNewAttempt(suppliesCustomer: true))
        let order = handle.requestOrderId
        let total = handle.requestTotal
        let reference = handle.requestReference

        handle.chargeFailed(Self.unknownOutcome)

        XCTAssertEqual(handle.requestAttempt, .retry)
        XCTAssertEqual(handle.requestReference, reference, "the retry names another payment")
        XCTAssertEqual(handle.requestOrderId, order)
        XCTAssertEqual(handle.requestTotal, total)
    }

    func testAnAnsweredFailureLeavesTheNextSubmitANewPayment() throws {
        let handle = try makeHandle()
        XCTAssertTrue(handle.startNewAttempt(suppliesCustomer: true))

        handle.chargeFailed(PayInFailure(PayabliPayInError.invalidInput("Refused."), operation: .capture))

        XCTAssertEqual(handle.requestAttempt, .newPayment)
    }

    func testDrawingAnAttemptAfterAnUnknownOutcomeIsANewPayment() throws {
        let handle = try makeHandle()
        XCTAssertTrue(handle.startNewAttempt(suppliesCustomer: true))
        handle.chargeFailed(Self.unknownOutcome)

        XCTAssertTrue(handle.startNewAttempt(suppliesCustomer: true))

        XCTAssertEqual(handle.requestAttempt, .newPayment)
    }

    /// Moving the customer switch answers a different question, so it leaves the
    /// attempt's identity alone. Without this the retry of the payment on screen
    /// would become a payment of its own.
    func testChangingTheCustomerKeepsTheAttemptItIsOn() throws {
        let handle = try makeHandle()
        XCTAssertTrue(handle.startNewAttempt(suppliesCustomer: true))
        handle.chargeFailed(Self.unknownOutcome)
        let order = handle.requestOrderId
        let total = handle.requestTotal

        handle.applyCustomerChange(suppliesCustomer: false)

        XCTAssertEqual(handle.requestAttempt, .retry, "the retry became a new payment with the customer")
        XCTAssertEqual(handle.requestOrderId, order, "the order changed with the customer")
        XCTAssertEqual(handle.requestTotal, total, "the amount changed with the customer")
        XCTAssertNil(handle.requestCustomerNumber, "the customer was still sent")
    }

    func testChangingTheCustomerBackNamesThePayerAgain() throws {
        let handle = try makeHandle()
        XCTAssertTrue(handle.startNewAttempt(suppliesCustomer: false))
        XCTAssertNil(handle.requestCustomerNumber)

        handle.applyCustomerChange(suppliesCustomer: true)

        XCTAssertNotNil(handle.requestCustomerNumber, "the customer never reached the request")
    }

    // MARK: - Several operations on one screen

    func testAChangedAmountGivesOnlyTheFlowOnScreenANewPayment() throws {
        let (capture, authorize) = try (makeHandle(), makeHandle(.authorize))
        var attempts = PayInAttempts()
        attempts.apply(amount: 10, to: capture, for: .capture, suppliesCustomer: true, source: "test")
        attempts.apply(amount: 10, to: authorize, for: .authorize, suppliesCustomer: true, source: "test")
        capture.chargeFailed(Self.unknownOutcome)
        authorize.chargeFailed(Self.unknownOutcome)

        attempts.apply(amount: 12, to: capture, for: .capture, suppliesCustomer: true, source: "test")

        XCTAssertEqual(capture.requestAttempt, .newPayment, "the flow on screen kept its retry for a new amount")
        XCTAssertEqual(capture.requestTotal, 12)
        XCTAssertEqual(authorize.requestAttempt, .retry, "a flow off screen lost its retry")
        XCTAssertEqual(authorize.requestTotal, 10)
    }

    /// Coming back to an operation reapplies the amount on screen. The attempt stays, so a retry is still read as a
    /// repeat of the payment that may have gone through.
    func testTheSameAmountKeepsTheFlowsAttempt() throws {
        let capture = try makeHandle()
        var attempts = PayInAttempts()
        attempts.apply(amount: 10, to: capture, for: .capture, suppliesCustomer: true, source: "test")
        capture.chargeFailed(Self.unknownOutcome)

        attempts.apply(amount: 10, to: capture, for: .capture, suppliesCustomer: true, source: "test")

        XCTAssertEqual(capture.requestAttempt, .retry, "reapplying the amount dropped the retry")
    }

    func testACompletedPaymentGivesItsOwnFlowANewPayment() throws {
        let (capture, authorize) = try (makeHandle(), makeHandle(.authorize))
        var attempts = PayInAttempts()
        attempts.apply(amount: 10, to: capture, for: .capture, suppliesCustomer: true, source: "test")
        attempts.apply(amount: 10, to: authorize, for: .authorize, suppliesCustomer: true, source: "test")
        capture.chargeFailed(Self.unknownOutcome)
        authorize.chargeFailed(Self.unknownOutcome)

        attempts.paymentCompleted(amount: 10, on: capture, for: .capture, suppliesCustomer: true, source: "test")

        XCTAssertEqual(capture.requestAttempt, .newPayment, "a completed payment left the next one a retry")
        XCTAssertEqual(authorize.requestAttempt, .retry, "another flow's attempt changed with the completion")
    }

    func testTheSameAttemptKeepsEverySettingButTheCustomer() {
        let current = PayabliPayInRequestConfiguration(
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 10),
            orderId: "order-1",
            paymentReference: "payment-1",
            attempt: .retry
        )

        let same = PayInRequests.sameAttempt(as: current, customerData: nil, attempt: current.attempt)

        XCTAssertEqual(same.attempt, .retry, "the retry became a new payment")
        XCTAssertEqual(same.paymentReference, "payment-1")
        XCTAssertEqual(same.orderId, "order-1")
    }

    private static let unknownOutcome = PayInFailure(
        PayabliPayInError.submissionInterrupted(type: .networkError, causeType: "test", paymentTransId: nil),
        operation: .capture
    )

    // MARK: -

    private func makeHandle(_ operation: PayabliPayInOperation = .capture) throws -> PayInFlowHandle {
        PayInFlowHandle(
            PayabliPayIn(
                session: PayabliSession(config: try PayabliConfig(
                    entryPoint: "test-entry",
                    environment: .sandbox,

                    tokenProvider: { "test-token" }
                )),
                operation: operation
            )
        )
    }
}

/// The request's own fields, for a test that has to see what a new attempt changed.
private extension PayInFlowHandle {
    var requestAttempt: PayabliAttempt? {
        flow.requestConfiguration?.attempt
    }

    var requestReference: String? {
        flow.requestConfiguration?.paymentReference
    }

    var requestOrderId: String? {
        flow.requestConfiguration?.orderId
    }

    var requestTotal: Double? {
        flow.requestConfiguration?.paymentDetails.totalAmount
    }

    var requestSource: String? {
        flow.requestConfiguration?.source
    }

    var requestCustomerNumber: String? {
        flow.requestConfiguration?.customerData?.customerNumber
    }
}

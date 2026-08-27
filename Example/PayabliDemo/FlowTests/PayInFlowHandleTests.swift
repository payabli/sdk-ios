import PayabliSDKPayInPaymentFlow
import XCTest

/// What drawing a new capture attempt does to the request the next submit carries.
///
/// One attempt is one payment however many times it is submitted: a resubmission
/// carries the same idempotency key, so the service answers from the attempt that
/// already reached it. Drawing a new attempt is the one action here that mints a
/// key, and therefore the one that can turn the next submit into a second payment.
///
/// The refusal during a submission is not covered, and cannot be from this target:
/// `isSubmitting` is `public private(set)`, and the initialiser that accepts a
/// transport is internal to the SDK, so nothing here can hold a submission open
/// without a live request. What is covered is every part reachable while idle.
@MainActor
final class PayInFlowHandleTests: XCTestCase {
    func testDrawingAnAttemptMintsAKeyThatWasNotThereBefore() {
        let handle = makeHandle()
        XCTAssertTrue(handle.startNewAttempt(suppliesCustomer: true))
        let first = try? XCTUnwrap(handle.requestKey)

        XCTAssertTrue(handle.startNewAttempt(suppliesCustomer: true))

        XCTAssertNotNil(first)
        XCTAssertNotEqual(handle.requestKey, first, "a new attempt reused the earlier key")
    }

    /// The key is the only field a new attempt is guaranteed to change. The order
    /// identifier names the device and the second, so two attempts inside one second
    /// share it, and the amount is drawn at random and can repeat.
    func testDrawingAnAttemptCarriesTheAttemptsOwnFields() {
        let handle = makeHandle()

        XCTAssertTrue(handle.startNewAttempt(suppliesCustomer: true))

        XCTAssertNotNil(handle.requestKey, "the attempt carries no key")
        XCTAssertNotNil(handle.requestOrderId, "the attempt names no order")
        XCTAssertEqual(handle.requestTotal.map { $0 > 0 }, true, "the attempt charges nothing")
    }

    /// Moving the customer switch answers a different question, so it leaves the
    /// attempt's identity alone. Without this the retry of the payment on screen
    /// would become a payment of its own.
    func testChangingTheCustomerKeepsTheAttemptItIsOn() {
        let handle = makeHandle()
        XCTAssertTrue(handle.startNewAttempt(suppliesCustomer: true))
        let key = handle.requestKey
        let order = handle.requestOrderId
        let total = handle.requestTotal

        handle.applyCustomerChange(suppliesCustomer: false)

        XCTAssertEqual(handle.requestKey, key, "the key changed with the customer")
        XCTAssertEqual(handle.requestOrderId, order, "the order changed with the customer")
        XCTAssertEqual(handle.requestTotal, total, "the amount changed with the customer")
        XCTAssertNil(handle.requestCustomerNumber, "the customer was still sent")
    }

    func testChangingTheCustomerBackNamesThePayerAgain() {
        let handle = makeHandle()
        XCTAssertTrue(handle.startNewAttempt(suppliesCustomer: false))
        XCTAssertNil(handle.requestCustomerNumber)

        handle.applyCustomerChange(suppliesCustomer: true)

        XCTAssertNotNil(handle.requestCustomerNumber, "the customer never reached the request")
    }

    // MARK: -

    private func makeHandle() -> PayInFlowHandle {
        PayInFlowHandle(
            PayabliPayInPaymentFlow(
                accessToken: "test-token",
                entryPoint: "test-entry",
                environment: DemoEnvironment.sandbox.sdkEnvironment,
                operation: .capture
            )
        )
    }
}

/// The request's own fields, for a test that has to see what a new attempt changed.
private extension PayInFlowHandle {
    var requestKey: String? {
        flow.requestConfiguration?.idempotencyKey
    }

    var requestOrderId: String? {
        flow.requestConfiguration?.orderId
    }

    var requestTotal: Double? {
        flow.requestConfiguration?.paymentDetails.totalAmount
    }

    var requestCustomerNumber: String? {
        flow.requestConfiguration?.customerData?.customerNumber
    }
}

import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// The payment members as an Objective-C caller reaches them: a request object in, a result or an `NSError` out.
@MainActor
final class PayInPaymentObjCBridgeTests: XCTestCase {
    private static let interrupted = Data(#"{"code":"E9999","reason":"Error","data":{"paymentTransId":"101-abc"}}"#.utf8)

    func testACaptureThroughObjectiveCSendsTheRequestAndReturnsTheResult() async {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let bridge = PayabliPayInObjC(component: PayInFixture.makeFlow(transport: transport, key: "reserved-1"))

        let (result, error) = await call { bridge.capture(PayabliPayInRequestObjC.cash(totalAmount: 10), completion: $0) }

        XCTAssertNil(error)
        XCTAssertEqual(result?.code, "A0000")
        XCTAssertEqual(transport.sentKeys, ["reserved-1"])
    }

    func testEveryPaymentMemberThroughObjectiveCReachesTheService() async {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let bridge = PayabliPayInObjC(component: PayInFixture.makeFlow(transport: transport, key: "reserved-1"))
        let card = PayabliPayInRequestObjC.card(
            cardNumber: "4111111111111111",
            expiration: "02/30",
            cardholderName: "Jane Doe",
            cvv: "999",
            billingZip: "12345",
            saveIfSuccess: false,
            totalAmount: 10
        )

        let authorized = await call { bridge.authorize(card, completion: $0) }
        let captured = await call {
            bridge.captureAuthorizedTransaction(
                PayabliPayInAuthorizedRequestObjC(transId: "t-1", totalAmount: 10),
                completion: $0
            )
        }
        let voided = await call { bridge.voidTransaction(transId: "t-1", completion: $0) }

        XCTAssertEqual([authorized.0?.code, captured.0?.code, voided.0?.code], ["A0000", "A0000", "A0000"])
        XCTAssertEqual(transport.count, 3)
    }

    func testAnUnknownOutcomeThroughObjectiveCCarriesTheTransactionUnderItsKey() async throws {
        let transport = RecordingIdempotencyTransport(body: Self.interrupted, status: 500)
        let bridge = PayabliPayInObjC(component: PayInFixture.makeFlow(transport: transport, key: "reserved-1"))

        let (result, error) = await call { bridge.capture(PayabliPayInRequestObjC.cash(totalAmount: 10), completion: $0) }

        XCTAssertNil(result)
        let failure = try XCTUnwrap(error)
        XCTAssertEqual(failure.domain, "com.payabli.payIn")
        XCTAssertEqual(failure.code, PayabliErrorType.serverError.number)
        XCTAssertEqual(failure.userInfo["paymentTransId"] as? String, "101-abc")
    }

    func testAPaymentErrorSaysWhetherThePaymentMayHaveBeenTaken() async throws {
        let open = PayabliPayInObjC(component: PayInFixture.makeFlow(
            transport: RecordingIdempotencyTransport(body: Self.interrupted, status: 500),
            key: "reserved-1"
        ))
        let declined = PayabliPayInObjC(component: PayInFixture.makeFlow(
            transport: RecordingIdempotencyTransport(body: PayInFixture.declined),
            key: "reserved-2"
        ))

        let (_, unknown) = await call { open.voidTransaction(transId: "t-1", completion: $0) }
        let (_, refused) = await call { declined.capture(PayabliPayInRequestObjC.cash(totalAmount: 10), completion: $0) }

        XCTAssertEqual(try XCTUnwrap(unknown).userInfo["capture"] as? Int, 1)
        XCTAssertEqual(try XCTUnwrap(refused).userInfo["capture"] as? Int, 0)
    }

    func testAnErrorFromACallThatMovesNoMoneyCarriesNoCapture() {
        let error = PayabliGenericError(type: .networkError, reason: "lost").toPayabliPayInNSError()

        XCTAssertNil(error.userInfo["capture"])
    }

    func testTheRequestCarriesEverySettingItIsGiven() {
        let request = PayabliPayInRequestObjC.cash(totalAmount: 12.5)
        request.serviceFee = 0.5
        request.surchargeFee = 0.25
        request.currency = "USD"
        request.orderId = "order-1"
        request.subscriptionId = 7
        request.paymentReference = "payment-1"
        request.attempt = .retry
        request.achValidation = true
        request.forceCustomerCreation = false
        let customer = PayabliPayInCustomerDataObjC()
        customer.customerNumber = "C-1"
        customer.additionalData = ["k": "v"]
        request.customerData = customer

        let options = request.toSwift().options

        XCTAssertEqual(options.paymentDetails.totalAmount, 12.5)
        XCTAssertEqual(options.paymentDetails.serviceFee, 0.5)
        XCTAssertEqual(options.paymentDetails.surchargeFee, 0.25)
        XCTAssertEqual(options.paymentDetails.currency, "USD")
        XCTAssertEqual(options.orderId, "order-1")
        XCTAssertEqual(options.subscriptionId, 7)
        XCTAssertEqual(options.paymentReference, "payment-1")
        XCTAssertEqual(options.attempt, .retry)
        XCTAssertEqual(options.achValidation, true)
        XCTAssertEqual(options.forceCustomerCreation, false)
        XCTAssertEqual(options.customerData?.customerNumber, "C-1")
        XCTAssertEqual(options.customerData?.additionalData, ["k": "v"])
    }

    func testAMethodKindTheFactoryDoesNotNameIsRefused() {
        XCTAssertNil(PayabliPayInRequestObjC.stored(storedMethodId: "s-1", method: "wallet", totalAmount: 1))
        XCTAssertNil(PayabliPayInRequestObjC.bankAccount(
            accountNumber: "1",
            accountType: "Brokerage",
            holderName: "Jane Doe",
            routingNumber: "021000021",
            secCode: nil,
            holderType: nil,
            totalAmount: 1
        ))
        XCTAssertNotNil(PayabliPayInRequestObjC.stored(storedMethodId: "s-1", method: "bankAccount", totalAmount: 1))
    }

    // MARK: -

    private func call(
        _ start: (@escaping (PayabliPayInResultObjC?, NSError?) -> Void) -> Void
    ) async -> (PayabliPayInResultObjC?, NSError?) {
        await withCheckedContinuation { continuation in
            start { result, error in continuation.resume(returning: (result, error)) }
        }
    }
}

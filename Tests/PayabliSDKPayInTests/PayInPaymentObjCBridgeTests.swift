import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// The payment members as an Objective-C caller reaches them: a request object in, a result or an `NSError` out.
@MainActor
final class PayInPaymentObjCBridgeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

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
            expiry: "02/30",
            holderName: "Jane Doe",
            securityCode: "999",
            postalCode: "12345",
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
        XCTAssertEqual(PayabliErrorTypeCode(rawValue: failure.code), .serverError)
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

    func testARetryNamingNoReferenceThroughObjectiveCIsRefusedUnsent() async throws {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let bridge = PayabliPayInObjC(component: PayInFixture.makeFlow(transport: transport, key: "reserved-1"))
        let request = PayabliPayInRequestObjC.cash(totalAmount: 10)
        request.attempt = .retry

        let (result, error) = await call { bridge.capture(request, completion: $0) }

        XCTAssertNil(result)
        let failure = try XCTUnwrap(error)
        XCTAssertEqual(failure.localizedDescription, "A retry must name the paymentReference of the payment it repeats.")
        XCTAssertEqual(failure.userInfo["capture"] as? Int, 0)
        XCTAssertEqual(transport.count, 0)
    }

    func testAPaymentReferenceOpenOnCaptureSaysThePaymentMayHaveBeenTaken() async throws {
        let bridge = PayabliPayInObjC(component: PayInFixture.makeFlow(
            transport: RecordingIdempotencyTransport(body: Self.interrupted, status: 500),
            key: "reserved-1"
        ))
        let request = PayabliPayInRequestObjC.cash(totalAmount: 10)
        request.paymentReference = "order-42"

        _ = await call { bridge.capture(request, completion: $0) }
        let (_, error) = await call { bridge.capture(request, completion: $0) }

        let refused = try XCTUnwrap(error)
        XCTAssertEqual(refused.code, PayabliErrorType.paymentReferenceOpen.number)
        XCTAssertEqual(refused.userInfo["capture"] as? Int, 1)
    }

    func testAPaymentReferenceOpenOnVoidSaysThePaymentMayHaveBeenTaken() async throws {
        let held = HeldOpenTransport()
        let first = PayInFixture.makeFlow(transport: held, key: "k1")
        let bridge = PayabliPayInObjC(component: PayInFixture.makeFlow(transport: held, key: "n1"))

        let sending = Task { try await first.voidTransaction("t-1") }
        await held.firstSendArrived()
        let (_, error) = await call { bridge.voidTransaction(transId: "t-1", completion: $0) }
        held.release()
        _ = try await sending.value

        let refused = try XCTUnwrap(error)
        XCTAssertEqual(refused.code, PayabliErrorType.paymentReferenceOpen.number)
        XCTAssertEqual(refused.userInfo["capture"] as? Int, 1)
        XCTAssertEqual(held.sentKeys, ["k1"])
    }

    func testARetryDescribingAnotherPaymentSaysThePaymentWasNotTaken() async throws {
        let bridge = PayabliPayInObjC(component: PayInFixture.makeFlow(
            transport: RecordingIdempotencyTransport(body: Self.interrupted, status: 500),
            key: "reserved-1"
        ))
        let first = PayabliPayInRequestObjC.cash(totalAmount: 10)
        first.paymentReference = "order-42"
        let retry = PayabliPayInRequestObjC.cash(totalAmount: 11)
        retry.paymentReference = "order-42"
        retry.attempt = .retry

        _ = await call { bridge.capture(first, completion: $0) }
        let (_, error) = await call { bridge.capture(retry, completion: $0) }

        let refused = try XCTUnwrap(error)
        XCTAssertEqual(refused.code, PayabliErrorType.retryNotSamePayment.number)
        XCTAssertEqual(refused.userInfo["capture"] as? Int, 0)
    }

    func testAnErrorFromACallThatMovesNoMoneyCarriesNoCapture() {
        let error = PayabliGenericError(type: .networkError, reason: "lost").toPayabliPayInNSError()

        XCTAssertNil(error.userInfo["capture"])
    }

    func testACancelledPaymentSaysThePaymentMayHaveBeenTaken() {
        let error = CancellationError().toPayabliPayInNSError(movesMoney: true)

        XCTAssertEqual(error.userInfo["capture"] as? Int, 1)
    }

    func testAnUnknownOutcomeThroughObjectiveCCarriesTheTransactionAndThePaymentsReference() async throws {
        let transport = RecordingIdempotencyTransport(body: Self.interrupted, status: 500)
        let bridge = PayabliPayInObjC(component: PayInFixture.makeFlow(transport: transport, key: "reserved-1"))
        let request = PayabliPayInRequestObjC.cash(totalAmount: 10)
        request.paymentReference = "order-42"

        let (_, error) = await call { bridge.capture(request, completion: $0) }

        let failure = try XCTUnwrap(error)
        XCTAssertEqual(failure.userInfo["paymentTransId"] as? String, "101-abc")
        XCTAssertEqual(failure.userInfo["paymentReference"] as? String, "order-42")
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

    /// The wrapper's factories build the SDK's own digit buffers from strings: no host can reach
    /// them, so the wrapper overwrites them at its teardown and each payment task overwrites the
    /// copies it was handed.
    func testTheWrapperOverwritesItsCardBuffersWhenItIsReleased() {
        let digits = autoreleasepool {
            let wrapper = PayabliPayInRequestObjC.card(
                cardNumber: "4111111111111111",
                expiry: "02/30",
                holderName: "Jane Doe",
                securityCode: "999",
                postalCode: "12345",
                saveIfSuccess: false,
                totalAmount: 10
            )
            return wrapper.paymentMethod.sensitiveDigits
        }

        XCTAssertEqual(digits.count, 2, "a card method holds its number and its security code")
        XCTAssertTrue(digits[0].isWiped, "the wrapper overwrote the card number when released")
        XCTAssertEqual(
            digits[0].rawCopy(), Array(repeating: 0, count: 16),
            "the card number is overwritten, not just released"
        )
        XCTAssertTrue(digits[1].isWiped, "the wrapper overwrote the security code when released")
        XCTAssertEqual(
            digits[1].rawCopy(), Array(repeating: 0, count: 3),
            "the security code is overwritten, not just released"
        )
    }

    func testTheWrapperOverwritesItsAccountNumberWhenItIsReleased() {
        let digits: [SensitiveDigits] = autoreleasepool {
            guard let wrapper = PayabliPayInRequestObjC.bankAccount(
                accountNumber: "1111111111",
                accountType: "Checking",
                holderName: "Jane Doe",
                routingNumber: "021000021",
                secCode: nil,
                holderType: nil,
                totalAmount: 10
            ) else { return [] }
            return wrapper.paymentMethod.sensitiveDigits
        }

        XCTAssertEqual(digits.count, 1, "a bank method holds its account number")
        XCTAssertTrue(digits[0].isWiped, "the wrapper overwrote the account number when released")
        XCTAssertEqual(
            digits[0].rawCopy(), Array(repeating: 0, count: 10),
            "the account number is overwritten, not just released"
        )
    }

    func testTheRequestHoldsItsOwnCopiesOfTheWrappersDigitBuffers() {
        let cardDigits: [SensitiveDigits] = autoreleasepool {
            let wrapper = PayabliPayInRequestObjC.card(
                cardNumber: "4111111111111111",
                expiry: "02/30",
                holderName: "Jane Doe",
                securityCode: "999",
                postalCode: "12345",
                saveIfSuccess: false,
                totalAmount: 10
            )
            return wrapper.toSwift().paymentMethod.sensitiveDigits
        }
        let bankDigits: [SensitiveDigits] = autoreleasepool {
            guard let wrapper = PayabliPayInRequestObjC.bankAccount(
                accountNumber: "1111111111",
                accountType: "Checking",
                holderName: "Jane Doe",
                routingNumber: "021000021",
                secCode: nil,
                holderType: nil,
                totalAmount: 10
            ) else { return [] }
            return wrapper.toSwift().paymentMethod.sensitiveDigits
        }

        XCTAssertEqual(cardDigits[0].length, 16, "the request's card number is its own copy")
        XCTAssertEqual(cardDigits[1].length, 3, "the request's security code is its own copy")
        XCTAssertEqual(bankDigits[0].length, 10, "the request's account number is its own copy")
    }

    func testTheChargeTaskClosesTheRequestsCardBuffersOnARefusal() async {
        let transport = RecordingIdempotencyTransport(
            failure: PayabliGenericError(type: .networkError, reason: "lost")
        )
        let bridge = PayabliPayInObjC(component: PayInFixture.makeFlow(transport: transport, key: "reserved-1"))
        let request = PayInFixture.request(cardOnly: true)
        let digits = request.paymentMethod.sensitiveDigits

        let (result, error) = await call { bridge.capture(request, completion: $0) }

        XCTAssertNil(result)
        XCTAssertNotNil(error)
        XCTAssertTrue(digits[0].isWiped, "the task closed the card number buffer")
        XCTAssertEqual(
            digits[0].rawCopy(), Array(repeating: 0, count: 19),
            "the card number is overwritten, not just released"
        )
        XCTAssertTrue(digits[1].isWiped, "the task closed the security code buffer")
        XCTAssertEqual(
            digits[1].rawCopy(), Array(repeating: 0, count: 3),
            "the security code is overwritten, not just released"
        )
    }

    func testTheAuthorizationTaskClosesTheRequestsCardBuffersOnAnApproval() async {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let bridge = PayabliPayInObjC(component: PayInFixture.makeFlow(transport: transport, key: "reserved-1"))
        let request = PayInFixture.request(cardOnly: true)
        let digits = request.paymentMethod.sensitiveDigits

        let (result, error) = await call { bridge.authorize(request, completion: $0) }

        XCTAssertNil(error)
        XCTAssertEqual(result?.code, "A0000")
        XCTAssertTrue(digits[0].isWiped, "the task closed the card number buffer on the success exit")
        XCTAssertEqual(
            digits[0].rawCopy(), Array(repeating: 0, count: 19),
            "the card number is overwritten on success, not just released"
        )
        XCTAssertTrue(digits[1].isWiped, "the task closed the security code buffer on the success exit")
        XCTAssertEqual(
            digits[1].rawCopy(), Array(repeating: 0, count: 3),
            "the security code is overwritten on success, not just released"
        )
    }

    func testARetryThroughTheSameWrapperStillCarriesItsDigits() async {
        let transport = RecordingIdempotencyTransport(body: PayInFixture.approved)
        let bridge = PayabliPayInObjC(component: PayInFixture.makeFlow(transport: transport, key: "reserved-1"))
        let wrapper = PayabliPayInRequestObjC.card(
            cardNumber: "4111111111111111",
            expiry: "02/30",
            holderName: "Jane Doe",
            securityCode: "999",
            postalCode: "12345",
            saveIfSuccess: false,
            totalAmount: 10
        )
        wrapper.paymentReference = "order-42"

        let first = await call { bridge.capture(wrapper, completion: $0) }
        wrapper.attempt = .retry
        let second = await call { bridge.capture(wrapper, completion: $0) }

        XCTAssertEqual([first.0?.code, second.0?.code], ["A0000", "A0000"])
        XCTAssertEqual(transport.count, 2, "the retry reached the service again")
        XCTAssertEqual(
            wrapper.paymentMethod.sensitiveDigits[0].length, 16,
            "the first charge spent its own copy, leaving the wrapper's digits for the retry"
        )
        XCTAssertEqual(
            wrapper.paymentMethod.sensitiveDigits[1].length, 3,
            "the first charge spent its own copy, leaving the wrapper's security code for the retry"
        )
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

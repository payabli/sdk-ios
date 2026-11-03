@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// A card-not-present failure is one of `PayabliPayInError`'s types, caught by that type or as the family.
final class PayInErrorTypesTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

    // MARK: - Caught by type

    func testEachTypeIsCaughtByItsOwnTypeAndByTheFamily() {
        let failure = PayabliPayInFailure(code: "D0329", reason: "Declined", httpStatusCode: 200)
        let cases: [(PayabliPayInError, PayabliErrorType)] = [
            (PayabliPayInError.InvalidInput(field: "paymentMethod.cardnumber", reason: "Bad"), .validation),
            (PayabliPayInError.Refused(failure: failure), .paymentDeclined),
            (PayabliPayInError.ServiceError(failure: PayabliPayInFailure(code: "E1001", httpStatusCode: 502)), .serverError),
            (PayabliPayInError.Undecodable(), .decodingError),
            (PayabliPayInError.Unsettled(cause: PayabliGenericError(type: .networkError, reason: "offline")), .networkError),
            (PayabliPayInError.AlreadySubmitting(), .validation),
            (PayabliPayInError.Interrupted(), .userCancelled)
        ]
        for (thrown, type) in cases {
            XCTAssertTrue(Self.caughtAsFamily(thrown), "\(Swift.type(of: thrown))")
            XCTAssertEqual(thrown.type, type, "\(Swift.type(of: thrown))")
        }
    }

    func testAnInvalidInputIsCaughtByItsTypeAndNamesItsField() throws {
        do {
            throw PayabliPayInError.InvalidInput(field: "paymentMethod.cardnumber", reason: "Bad number")
        } catch let error as PayabliPayInError.InvalidInput {
            XCTAssertEqual(error.field, "paymentMethod.cardnumber")
            XCTAssertEqual(error.reason, "Bad number")
        } catch {
            XCTFail("caught as \(error)")
        }
    }

    func testARefusalReadsTheAnswersStatusAndCodeThroughThePublicProtocol() {
        let refused: any Error = PayabliPayInError.Refused(
            failure: PayabliPayInFailure(code: "D0329", explanation: "Declined by the issuer.", httpStatusCode: 200)
        )

        let error = refused as? any PayabliError

        XCTAssertEqual(error?.httpStatus, 200)
        XCTAssertEqual(error?.rawCode, "D0329")
        XCTAssertEqual(error?.reason, "Declined by the issuer.")
    }

    func testAnUnsettledFailureCarriesItsCausesTypeStatusAndCode() {
        let cause = PayabliGenericError(type: .serverError, reason: "Bad gateway", httpStatus: 502, rawCode: "E9999")

        let unsettled = PayabliPayInError.Unsettled(cause: cause, paymentTransId: "trans-1", paymentReference: "ref-1")

        XCTAssertEqual(unsettled.type, .serverError)
        XCTAssertEqual(unsettled.httpStatus, 502)
        XCTAssertEqual(unsettled.rawCode, "E9999")
        XCTAssertEqual(unsettled.paymentTransId, "trans-1")
        XCTAssertEqual(unsettled.paymentReference, "ref-1")
        XCTAssertEqual(RedactedCause.simpleName(unsettled.redactedCause.originalType), "PayabliGenericError")
    }

    // MARK: - Where the client throws each

    func testAnUnapprovedAnswerInTheDeclineFamilyIsARefusal() async throws {
        let error = await captureFailure(status: 200, body: #"{"code":"D0329","reason":"Declined"}"#)

        let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "\(error)")
        XCTAssertEqual(refused.failure.code, "D0329")
        XCTAssertEqual(refused.httpStatus, 200)
        XCTAssertEqual(refused.rawCode, "D0329")
    }

    func testAnUnapprovedAnswerOutsideTheDeclineFamilyIsAServiceErrorThatLeavesTheOutcomeOpen() async throws {
        let error = await captureFailure(status: 200, body: #"{"code":"E1001","reason":"Processor unavailable"}"#)

        let open = try XCTUnwrap(error as? PayInOpenOutcome, "\(error)")
        let serviceError = try XCTUnwrap(open.cause as? PayabliPayInError.ServiceError, "\(open.cause)")
        XCTAssertEqual(serviceError.failure.code, "E1001")
        XCTAssertEqual(serviceError.type, .serverError)
        XCTAssertEqual(open.interruption.httpStatus, 200)
        XCTAssertEqual(open.interruption.rawCode, "E1001")
    }

    func testAStoreRefusedWithASuccessStatusIsARefusalWithNoCode() async throws {
        let error = await storeFailure(status: 200, body: """
        {"isSuccess":false,"responseText":"Declined","responseData":{"resultCode":3,"resultText":"Card rejected"}}
        """)

        let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "\(error)")
        XCTAssertEqual(refused.reason, "Card rejected")
        XCTAssertEqual(refused.failure.httpStatusCode, 200)
        XCTAssertEqual(refused.httpStatus, 200)
        XCTAssertNil(refused.failure.code)
        XCTAssertNil(refused.rawCode)
    }

    func testAStoreRefusedWithNoReasonGivesTheFallbackReason() async throws {
        let error = await storeFailure(status: 200, body: """
        {"isSuccess":false,"responseText":"  ","responseData":{"resultCode":3,"resultText":""}}
        """)

        let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "\(error)")
        XCTAssertEqual(refused.reason, "Unable to save payment method.")
        XCTAssertEqual(refused.httpStatus, 200)
    }

    func testAStoreFieldRefusedBeforeSendingNamesTheField() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: "{}")
        let client = PayInPaymentFlowTokenStorageClient(transport: transport)
        let card = PayabliPayInCardData(
            cardNumber: "123",
            expiryMonth: 2,
            expiryYear: 2035,
            securityCode: "999",
            holderName: "John Cassian",
            postalCode: "12345"
        )

        let error = await PayInFixture.failure { _ = try await client.addMethod(entryPoint: "entry", paymentMethod: .card(card)) }

        let invalid = try XCTUnwrap(error as? PayabliPayInError.InvalidInput, "\(error)")
        XCTAssertEqual(invalid.field, "paymentMethod.cardnumber")
        let sent = await transport.requests
        XCTAssertTrue(sent.isEmpty)
    }

    func testAStoreAnswerThatWontDecodeIsUndecodableAtItsStatus() async throws {
        let error = await storeFailure(status: 200, body: "not json")

        let undecodable = try XCTUnwrap(error as? PayabliPayInError.Undecodable, "\(error)")
        XCTAssertEqual(undecodable.httpStatus, 200)
        XCTAssertNil(undecodable.rawCode)
    }

    // MARK: - A cancelled send

    @MainActor
    func testAFormSendCancelledBeforeItLeftIsInterrupted() async throws {
        let flow = PayInFixture.makeFlow(transport: RecordingIdempotencyTransport(failure: CancellationError()), key: "k")

        let error = await PayInFixture.failure {
            _ = try await flow.submitConfigured(.card(Self.card), options: PayabliPayInTokenStorageOptions(), origin: .form)
        }

        let interrupted = try XCTUnwrap(error as? PayabliPayInError.Interrupted, "\(error)")
        XCTAssertEqual(interrupted.type, .userCancelled)
    }

    @MainActor
    func testADirectCallCancelledBeforeItLeftThrowsItsCancellation() async {
        let flow = PayInFixture.makeFlow(transport: RecordingIdempotencyTransport(failure: CancellationError()), key: "k")

        let error = await PayInFixture.failure {
            _ = try await flow.submitConfigured(.card(Self.card), options: PayabliPayInTokenStorageOptions(), origin: .direct)
        }

        XCTAssertTrue(error is CancellationError, "\(error)")
    }

    // MARK: - Support

    private static let card = PayabliPayInCardData(
        cardNumber: "4111 1111 1111 1111",
        expiryMonth: 2,
        expiryYear: 2035,
        securityCode: "999",
        holderName: "John Cassian",
        postalCode: "12345"
    )

    private static func caughtAsFamily(_ error: PayabliPayInError) -> Bool {
        do {
            throw error
        } catch is PayabliPayInError {
            return true
        } catch {
            return false
        }
    }

    private func captureFailure(status: Int, body: String) async -> any Error {
        let client = PayInPaymentFlowClient(transport: MockPaymentCaptureTransport(statusCode: status, responseBody: body))
        return await PayInFixture.failure {
            _ = try await client.capture(entryPoint: "entry", request: PayInFixture.request(cardOnly: true), idempotencyKey: "k")
        }
    }

    private func storeFailure(status: Int, body: String) async -> any Error {
        let client = PayInPaymentFlowTokenStorageClient(
            transport: MockPaymentCaptureTransport(statusCode: status, responseBody: body)
        )
        return await PayInFixture.failure {
            _ = try await client.addMethod(entryPoint: "entry", paymentMethod: .card(Self.card))
        }
    }
}

@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// A card-not-present failure read from an answer carries that answer's status and the service's code.
@MainActor
final class PayInErrorStatusTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

    // MARK: - Capture

    func testARefusedPaymentCarriesTheAnswersStatusAndCode() async throws {
        let client = PayInPaymentFlowClient(transport: MockPaymentCaptureTransport(
            statusCode: 402,
            responseBody: #"{"code":"D0200","reason":"Insufficient Funds","data":null,"token":null}"#
        ))

        let error = await failure { _ = try await client.capture(entryPoint: "entry", request: Self.request, idempotencyKey: "k-1") }

        let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "got \(error)")
        XCTAssertEqual(refused.httpStatus, 402)
        XCTAssertEqual(refused.rawCode, "D0200")
    }

    func testACaptureAnswered402IsRefusedWhateverItsCode() async throws {
        let cases: [(body: String, rawCode: String?)] = [
            (#"{"code":"E1001","reason":"Declined","data":null,"token":null}"#, "E1001"),
            (#"{"reason":"Declined"}"#, nil),
            ("", nil)
        ]
        for (index, answer) in cases.enumerated() {
            let client = PayInPaymentFlowClient(transport: MockPaymentCaptureTransport(statusCode: 402, responseBody: answer.body))

            let error = await failure {
                _ = try await client.capture(entryPoint: "entry", request: Self.request, idempotencyKey: "k-402-\(index)")
            }

            let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "body \(answer.body): got \(error)")
            XCTAssertEqual(refused.type, .paymentDeclined, "body \(answer.body)")
            XCTAssertEqual(refused.httpStatus, 402, "body \(answer.body)")
            XCTAssertEqual(refused.rawCode, answer.rawCode, "body \(answer.body)")
        }
    }

    func testA402IsRefusedWhenItsBodyNamesAnApprovalOrAnotherStatus() async throws {
        let bodies = [
            #"{"code":"A0000","reason":"Approved","data":null,"token":null}"#,
            #"{"isSuccess":false,"responseText":"Declined","responseCode":5001}"#,
            #"{"status":400,"reason":"Declined"}"#
        ]
        for (index, body) in bodies.enumerated() {
            let client = PayInPaymentFlowClient(transport: MockPaymentCaptureTransport(statusCode: 402, responseBody: body))

            let error = await failure {
                _ = try await client.capture(entryPoint: "entry", request: Self.request, idempotencyKey: "k-402-b\(index)")
            }

            let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "body \(body): got \(error)")
            XCTAssertEqual(refused.type, .paymentDeclined, "body \(body)")
            XCTAssertEqual(refused.httpStatus, 402, "body \(body)")
        }
    }

    func testAnOlderEnvelopesDeclineAt402CarriesItsResponseCode() async throws {
        let client = PayInPaymentFlowClient(transport: MockPaymentCaptureTransport(
            statusCode: 402,
            responseBody: #"{"isSuccess":false,"responseText":"Declined","responseCode":5001}"#
        ))

        let error = await failure { _ = try await client.capture(entryPoint: "entry", request: Self.request, idempotencyKey: "k-legacy") }

        let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "got \(error)")
        XCTAssertEqual(refused.rawCode, "5001")
    }

    func testARefusalNamesTheTransactionItsAnswerNamed() async throws {
        let answers: [(status: Int, body: String)] = [
            (402, #"{"code":"D0200","reason":"Insufficient Funds","data":{"paymentTransId":" trans-402 "}}"#),
            (200, #"{"code":"D0329","reason":"Declined","data":{"paymentTransId":" trans-402 "}}"#),
            (400, #"{"code":"E9005","reason":"Blocked","data":{"paymentTransId":" trans-402 "}}"#),
            (402, #"{"reason":"Declined","data":{"paymentTransId":" trans-402 "}}"#)
        ]
        for (index, answer) in answers.enumerated() {
            let client = PayInPaymentFlowClient(transport: MockPaymentCaptureTransport(
                statusCode: answer.status,
                responseBody: answer.body
            ))

            let error = await failure {
                _ = try await client.capture(entryPoint: "entry", request: Self.request, idempotencyKey: "k-tx-\(index)")
            }

            let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "\(answer.status): got \(error)")
            XCTAssertEqual(refused.failure.paymentTransId, "trans-402", "\(answer.status)")
        }
    }

    func testAServiceErrorNamesTheTransactionItsAnswerNamed() async throws {
        let client = PayInPaymentFlowClient(transport: MockPaymentCaptureTransport(
            statusCode: 403,
            responseBody: #"{"code":"E4003","reason":"Forbidden","data":{"paymentTransId":"trans-403"}}"#
        ))

        let error = await failure { _ = try await client.capture(entryPoint: "entry", request: Self.request, idempotencyKey: "k-tx-s") }

        let service = try XCTUnwrap(error as? PayabliPayInError.ServiceError, "got \(error)")
        XCTAssertEqual(service.failure.paymentTransId, "trans-403")
    }

    func testARefusalNamingNoTransactionOrABlankOneCarriesNone() async throws {
        let bodies = [
            #"{"code":"D0200","reason":"Insufficient Funds","data":null}"#,
            #"{"code":"D0200","reason":"Insufficient Funds","data":{"paymentTransId":"  "}}"#
        ]
        for (index, body) in bodies.enumerated() {
            let client = PayInPaymentFlowClient(transport: MockPaymentCaptureTransport(statusCode: 402, responseBody: body))

            let error = await failure {
                _ = try await client.capture(entryPoint: "entry", request: Self.request, idempotencyKey: "k-tx-n\(index)")
            }

            let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "body \(body): got \(error)")
            XCTAssertNil(refused.failure.paymentTransId, "body \(body)")
        }
    }

    func testAnAuthorizationAnswered402WithNoDeclineCodeIsRefused() async throws {
        let client = PayInPaymentFlowClient(transport: MockPaymentCaptureTransport(
            statusCode: 402,
            responseBody: #"{"code":"E1001","reason":"Declined","data":null,"token":null}"#
        ))

        let error = await failure { _ = try await client.authorize(entryPoint: "entry", request: Self.request, idempotencyKey: "k-402-a") }

        let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "got \(error)")
        XCTAssertEqual(refused.type, .paymentDeclined)
        XCTAssertEqual(refused.httpStatus, 402)
        XCTAssertEqual(refused.rawCode, "E1001")
    }

    func testA402WhoseCodeLeavesTheOutcomeOpenIsUnsettledNeverRefused() async throws {
        let answers: [(code: String, type: PayabliErrorType)] = [("E9060", .unknown), ("E9999", .serverError)]
        for answer in answers {
            for route in ["capture", "authorize"] {
                let body = #"{"code":"\#(answer.code)","reason":"Unknown","data":{"paymentTransId":"trans-open"}}"#
                let transport = RecordingIdempotencyTransport(body: Data(body.utf8), status: 402)
                let flow = PayInFixture.makeFlow(transport: transport, key: "k-open-\(answer.code)-\(route)")

                let error = await PayInFixture.failure(from: {
                    if route == "capture" {
                        _ = try await flow.capture(PayInFixture.request(cardOnly: true))
                    } else {
                        _ = try await flow.authorize(PayInFixture.request(cardOnly: true))
                    }
                })

                let unsettled = try XCTUnwrap(error as? PayabliPayInError.Unsettled, "\(answer.code) \(route): got \(error)")
                XCTAssertEqual(unsettled.type, answer.type, "\(answer.code) \(route)")
                XCTAssertEqual(unsettled.httpStatus, 402, "\(answer.code) \(route)")
                XCTAssertEqual(unsettled.rawCode, answer.code, "\(answer.code) \(route)")
                XCTAssertEqual(unsettled.paymentTransId, "trans-open", "\(answer.code) \(route)")
                XCTAssertEqual(RedactedCause.simpleName(unsettled.redactedCause.originalType), "ServiceError", "\(answer.code) \(route)")
            }
        }
    }

    func testA402WhoseOtherFieldsCannotBeReadKeepsItsCode() async throws {
        let client = PayInPaymentFlowClient(transport: MockPaymentCaptureTransport(
            statusCode: 402,
            responseBody: #"{"code":"E1001","reason":42,"data":{"paymentTransId":"trans-bad"}}"#
        ))

        let error = await failure { _ = try await client.capture(entryPoint: "entry", request: Self.request, idempotencyKey: "k-bad") }

        let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "got \(error)")
        XCTAssertEqual(refused.httpStatus, 402)
        XCTAssertEqual(refused.rawCode, "E1001")
        XCTAssertEqual(refused.failure.paymentTransId, "trans-bad")
    }

    func testA402WhoseOtherFieldsCannotBeReadStillLeavesAnOpenCodeOpen() async throws {
        let body = #"{"code":"E9060","reason":42,"data":{"paymentTransId":"trans-bad"}}"#
        let flow = PayInFixture.makeFlow(transport: RecordingIdempotencyTransport(body: Data(body.utf8), status: 402), key: "k-bad-open")

        let error = await PayInFixture.failure(from: { _ = try await flow.capture(PayInFixture.request(cardOnly: true)) })

        let unsettled = try XCTUnwrap(error as? PayabliPayInError.Unsettled, "got \(error)")
        XCTAssertEqual(unsettled.type, .unknown)
        XCTAssertEqual(unsettled.rawCode, "E9060")
        XCTAssertEqual(unsettled.paymentTransId, "trans-bad")
    }

    func testAServiceErrorAnswered402WithAnOpenCodeIsTypedByTheCode() {
        let cases: [(code: String, type: PayabliErrorType)] = [("E9060", .unknown), ("E9999", .serverError), ("E1001", .paymentDeclined)]
        for answer in cases {
            let failure = PayabliPayInFailure(code: answer.code, httpStatusCode: 402)

            XCTAssertEqual(PayabliPayInError.ServiceError(failure: failure).type, answer.type, answer.code)
        }
    }

    func testACaptureAnswerThatCannotBeReadIsUndecodableAtItsStatus() async throws {
        let client = PayInPaymentFlowClient(transport: MockPaymentCaptureTransport(statusCode: 200, responseBody: "not json"))

        let error = await failure { _ = try await client.capture(entryPoint: "entry", request: Self.request, idempotencyKey: "k-2") }

        let open = try XCTUnwrap(error as? PayInOpenOutcome, "got \(error)")
        let undecodable = try XCTUnwrap(open.cause as? PayabliPayInError.Undecodable, "got \(open.cause)")
        XCTAssertEqual(undecodable.httpStatus, 200)
        XCTAssertNil(undecodable.rawCode)
    }

    func testATransactionReadThatCannotBeReadKeepsItsStatus() async throws {
        let client = PayInPaymentFlowClient(transport: MockPaymentCaptureTransport(statusCode: 200, responseBody: "not json"))

        let error = await failure { _ = try await client.details(transId: "trans-1") }

        let payabli = try XCTUnwrap(error as? any PayabliError)
        XCTAssertEqual(payabli.type, .decodingError)
        XCTAssertEqual(payabli.httpStatus, 200)
        XCTAssertNil(payabli.rawCode)
    }

    func testATransactionTheCallerMayNotReadCarriesItsStatusAndCode() async throws {
        let client = PayInPaymentFlowClient(
            transport: MockPaymentCaptureTransport(statusCode: 401, responseBody: #"{"responseCode":9001}"#)
        )

        let error = await failure { _ = try await client.details(transId: "trans-1") }

        let payabli = try XCTUnwrap(error as? any PayabliError)
        XCTAssertEqual(payabli.type, .permissionDenied)
        XCTAssertEqual(payabli.httpStatus, 401)
        XCTAssertEqual(payabli.rawCode, "9001")
    }

    func testATransactionNotVisibleCarriesItsStatusAndCode() async throws {
        let client = PayInPaymentFlowClient(
            transport: MockPaymentCaptureTransport(statusCode: 400, responseBody: #"{"responseCode":7001}"#)
        )

        let error = await failure { _ = try await client.details(transId: "trans-1") }

        let payabli = try XCTUnwrap(error as? any PayabliError)
        XCTAssertEqual(payabli.type, .transactionNotFound)
        XCTAssertEqual(payabli.httpStatus, 400)
        XCTAssertEqual(payabli.rawCode, "7001")
    }

    func testAPascalCaseReadRefusalCarriesItsCode() async throws {
        for (status, code, type) in [(401, 9001, PayabliErrorType.permissionDenied), (400, 7001, .transactionNotFound)] {
            let client = PayInPaymentFlowClient(
                transport: MockPaymentCaptureTransport(statusCode: status, responseBody: #"{"ResponseCode":\#(code)}"#)
            )

            let error = await failure { _ = try await client.details(transId: "trans-1") }

            let payabli = try XCTUnwrap(error as? any PayabliError)
            XCTAssertEqual(payabli.type, type)
            XCTAssertEqual(payabli.httpStatus, status)
            XCTAssertEqual(payabli.rawCode, String(code))
        }
    }

    func testAnUnclassifiedStatusOnACaptureLeavesTheOutcomeOpenWithItsStatusAndCode() async throws {
        let transport = RecordingIdempotencyTransport(body: Data(#"{"code":"E1001"}"#.utf8), status: 418)
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-418")

        let error = await PayInFixture.failure(from: { _ = try await flow.capture(PayInFixture.request()) })

        let unsettled = try XCTUnwrap(error as? PayabliPayInError.Unsettled, "got \(error)")
        XCTAssertEqual(unsettled.type, .unknown)
        XCTAssertEqual(unsettled.httpStatus, 418)
        XCTAssertEqual(unsettled.rawCode, "E1001")
    }

    func testAServerErrorNamingACodeOnACaptureIsUnsettledWithThatStatusAndCode() async throws {
        let transport = RecordingIdempotencyTransport(body: Data(#"{"code":"E5001","title":"Bad gateway"}"#.utf8), status: 502)
        let flow = PayInFixture.makeFlow(transport: transport, key: "reserved-502")

        let error = await PayInFixture.failure(from: { _ = try await flow.capture(PayInFixture.request()) })

        let unsettled = try XCTUnwrap(error as? PayabliPayInError.Unsettled, "got \(error)")
        XCTAssertEqual(unsettled.httpStatus, 502)
        XCTAssertEqual(unsettled.rawCode, "E5001")
    }

    func testARefusedKeyAnsweredWithoutABodyIsAConflictAtItsStatusWithNoCode() async throws {
        let client = PayInPaymentFlowClient(transport: MockPaymentCaptureTransport(statusCode: 409, responseBody: ""))

        let error = await failure { _ = try await client.capture(entryPoint: "entry", request: Self.request, idempotencyKey: "k-3") }

        let open = try XCTUnwrap(error as? PayInOpenOutcome, "got \(error)")
        let conflict = try XCTUnwrap(open.cause as? PayabliGenericError, "got \(open.cause)")
        XCTAssertEqual(conflict.type, .conflict)
        XCTAssertEqual(conflict.httpStatus, 409)
        XCTAssertNil(conflict.rawCode)
    }

    // MARK: - Storing a method

    func testAStoreBlockedByFraudControlIsADeclineCarryingItsStatusAndCode() async throws {
        let client = PayInPaymentFlowTokenStorageClient(transport: MockPaymentCaptureTransport(
            statusCode: 400,
            responseBody: #"{"isSuccess":false,"responseText":"Blocked","responseCode":9005}"#
        ))

        let error = await failure { _ = try await client.addMethod(entryPoint: "entry", paymentMethod: .card(Self.card)) }

        let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "got \(error)")
        XCTAssertEqual(refused.type, .paymentDeclined)
        XCTAssertEqual(refused.httpStatus, 400)
        XCTAssertEqual(refused.rawCode, "9005")
    }

    func testAStoreBlockedByFraudControlWithNoTextIsStillADecline() async throws {
        let client = PayInPaymentFlowTokenStorageClient(transport: MockPaymentCaptureTransport(
            statusCode: 400,
            responseBody: #"{"responseCode":9005}"#
        ))

        let error = await failure { _ = try await client.addMethod(entryPoint: "entry", paymentMethod: .card(Self.card)) }

        let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "got \(error)")
        XCTAssertEqual(refused.httpStatus, 400)
        XCTAssertEqual(refused.rawCode, "9005")
    }

    func testAStoreBlockedByFraudControlIsADeclineWhicheverFieldNamesTheCode() async throws {
        let client = PayInPaymentFlowTokenStorageClient(transport: MockPaymentCaptureTransport(
            statusCode: 400,
            responseBody: #"{"code":"E1001","responseCode":9005,"responseText":"Blocked"}"#
        ))

        let error = await failure { _ = try await client.addMethod(entryPoint: "entry", paymentMethod: .card(Self.card)) }

        let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "got \(error)")
        XCTAssertEqual(refused.httpStatus, 400)
        XCTAssertEqual(refused.rawCode, "9005")
    }

    func testAStoreBlockedByFraudControlInResponseCodeWithNoTextIsStillADecline() async throws {
        let client = PayInPaymentFlowTokenStorageClient(transport: MockPaymentCaptureTransport(
            statusCode: 400,
            responseBody: #"{"code":"E1001","responseCode":9005}"#
        ))

        let error = await failure { _ = try await client.addMethod(entryPoint: "entry", paymentMethod: .card(Self.card)) }

        let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "got \(error)")
        XCTAssertEqual(refused.httpStatus, 400)
        XCTAssertEqual(refused.rawCode, "9005")
    }

    func testAStoreBadRequestWithNoTextKeepsItsCode() async throws {
        let client = PayInPaymentFlowTokenStorageClient(transport: MockPaymentCaptureTransport(
            statusCode: 400,
            responseBody: #"{"responseCode":9001}"#
        ))

        let error = await failure { _ = try await client.addMethod(entryPoint: "entry", paymentMethod: .card(Self.card)) }

        let payabli = try XCTUnwrap(error as? any PayabliError)
        XCTAssertEqual(payabli.type, .validation)
        XCTAssertEqual(payabli.rawCode, "9001")
    }

    func testAnyOtherBadRequestOnAStoreStaysAValidationErrorWithItsStatusAndCode() async throws {
        let client = PayInPaymentFlowTokenStorageClient(transport: MockPaymentCaptureTransport(
            statusCode: 400,
            responseBody: #"{"isSuccess":false,"responseText":"Bad card","responseCode":9001}"#
        ))

        let error = await failure { _ = try await client.addMethod(entryPoint: "entry", paymentMethod: .card(Self.card)) }

        XCTAssertNil(error as? PayabliPayInError.Refused)
        let payabli = try XCTUnwrap(error as? any PayabliError)
        XCTAssertEqual(payabli.type, .validation)
        XCTAssertEqual(payabli.httpStatus, 400)
        XCTAssertEqual(payabli.rawCode, "9001")
    }

    // MARK: - Fixtures

    private static let request = PayInFixture.request(cardOnly: true)

    private static let card = PayabliPayInCardData(
        cardNumber: "4111 1111 1111 1111",
        expiryMonth: 2,
        expiryYear: 2037,
        securityCode: "123",
        holderName: "Test Holder",
        postalCode: "12345"
    )

    private func failure(_ body: () async throws -> Void) async -> any Error {
        do {
            try await body()
        } catch {
            return error
        }
        XCTFail("expected a failure")
        return CancellationError()
    }
}

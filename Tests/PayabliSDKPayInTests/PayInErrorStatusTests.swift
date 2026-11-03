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

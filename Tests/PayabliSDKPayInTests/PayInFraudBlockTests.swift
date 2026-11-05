@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

/// A payer blocked by fraud control is a decline on every money route, decided by the code; a payment or an
/// authorization answered 401 with it is the caller's refusal.
@MainActor
final class PayInFraudBlockTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

    // MARK: - Answered 400

    func testACaptureBlockedByFraudControlIsADeclineAtItsStatusAndCode() async throws {
        for code in ["E9005", "E9051"] {
            let client = PayInPaymentFlowClient(transport: MockPaymentCaptureTransport(statusCode: 400, responseBody: Self.block(code)))

            let error = await failure {
                _ = try await client.capture(entryPoint: "entry", request: Self.request, idempotencyKey: "k-\(code)")
            }

            let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "\(code): got \(error)")
            XCTAssertEqual(refused.type, .paymentDeclined, code)
            XCTAssertEqual(refused.httpStatus, 400, code)
            XCTAssertEqual(refused.rawCode, code)
            XCTAssertEqual(refused.failure.reason, "Blocked", code)
        }
    }

    func testAnAuthorizationBlockedByFraudControlIsADecline() async throws {
        let client = PayInPaymentFlowClient(transport: MockPaymentCaptureTransport(statusCode: 400, responseBody: Self.block("E9051")))

        let error = await failure { _ = try await client.authorize(entryPoint: "entry", request: Self.request, idempotencyKey: "k-a") }

        let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "got \(error)")
        XCTAssertEqual(refused.httpStatus, 400)
        XCTAssertEqual(refused.rawCode, "E9051")
    }

    func testAVoidBlockedByFraudControlIsADecline() async throws {
        let client = PayInPaymentFlowClient(transport: MockPaymentCaptureTransport(statusCode: 400, responseBody: Self.block("E9005")))

        let error = await failure { _ = try await client.void(transId: "101-abc", idempotencyKey: "k-v") }

        let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "got \(error)")
        XCTAssertEqual(refused.rawCode, "E9005")
    }

    func testAnyOtherBadRequestOnACaptureStaysAValidationError() async throws {
        let client = PayInPaymentFlowClient(transport: MockPaymentCaptureTransport(statusCode: 400, responseBody: Self.block("E1001")))

        let error = await failure { _ = try await client.capture(entryPoint: "entry", request: Self.request, idempotencyKey: "k-o") }

        XCTAssertNil(error as? PayabliPayInError.Refused)
        let payabli = try XCTUnwrap(error as? any PayabliError, "got \(error)")
        XCTAssertEqual(payabli.type, .validation)
        XCTAssertEqual(payabli.httpStatus, 400)
        XCTAssertEqual(payabli.rawCode, "E1001")
    }

    // MARK: - Answered 401

    func testACaptureAnswered401WithAFraudBlockIsADeclineWithNoRefreshOrReplay() async throws {
        for code in ["E9005", "E9051"] {
            let http = AnsweringTransport(statusCode: 401, body: Self.block(code))
            let tokens = CountingTokens()
            let client = try Self.client(over: http, tokens: tokens)

            let error = await failure {
                _ = try await client.capture(entryPoint: "entry", request: Self.request, idempotencyKey: "k-\(code)")
            }

            let refused = try XCTUnwrap(error as? PayabliPayInError.Refused, "\(code): got \(error)")
            XCTAssertEqual(refused.type, .paymentDeclined, code)
            XCTAssertEqual(refused.httpStatus, 401, code)
            XCTAssertEqual(refused.rawCode, code)
            let sends = await http.count
            XCTAssertEqual(sends, 1, "\(code): no replay")
            let issued = await tokens.issued
            XCTAssertEqual(issued, 0, "\(code): no refresh")
        }
    }

    func testACaptureAnswered401WithAnyOtherBodyStillRefreshesAndReplays() async throws {
        let http = AnsweringTransport(statusCode: 401, body: Self.block("E1001"))
        let tokens = CountingTokens()
        let client = try Self.client(over: http, tokens: tokens)

        _ = await failure { _ = try await client.capture(entryPoint: "entry", request: Self.request, idempotencyKey: "k-r") }

        let sends = await http.count
        XCTAssertEqual(sends, 2, "the payment and its replay")
        let issued = await tokens.issued
        XCTAssertGreaterThan(issued, 0, "the provider is asked for a new token")
    }

    func testARetryBlockedByFraudControlAt401IsADeclineAndReleasesTheKey() async throws {
        for code in ["E9005", "E9051"] {
            PayInKeyStore.process.forgetHeld()
            let transport = ScriptedTransport()
            transport.script = [.lost, .fraudBlocked401(code), .approved]
            let flow = PayabliPayIn(entryPoint: "entry", environment: .sandbox, transport: transport)
            var minted = 0
            flow.newIdempotencyKey = {
                minted += 1
                return "k\(minted)"
            }

            _ = await failure { _ = try await flow.capture(Self.payment(.newPayment)) }
            let blocked = await failure { _ = try await flow.capture(Self.payment(.retry)) }
            _ = try await flow.capture(Self.payment(.retry))

            let refused = try XCTUnwrap(blocked as? PayabliPayInError.Refused, "\(code): got \(blocked)")
            XCTAssertEqual(refused.type, .paymentDeclined, code)
            XCTAssertEqual(refused.httpStatus, 401, code)
            XCTAssertEqual(refused.rawCode, code)
            XCTAssertEqual(transport.sentKeys, ["k1", "k1", "k2"], "\(code): the decline released the held key")
        }
    }

    func testOnlyAPaymentOrAnAuthorizationNamesA401FraudBlockAsTheCallers() async throws {
        let transport = MockPaymentCaptureTransport(statusCode: 200, responseBody: Self.approved)
        let client = PayInPaymentFlowClient(transport: transport)
        _ = try await client.capture(entryPoint: "entry", request: Self.request, idempotencyKey: "k-1")
        _ = try await client.authorize(entryPoint: "entry", request: Self.request, idempotencyKey: "k-2")
        _ = try await client.void(transId: "101-abc", idempotencyKey: "k-3")
        let requests = await transport.requests
        XCTAssertEqual(requests.count, 3)

        for request in requests.prefix(2) {
            XCTAssertTrue(request.isCallerRefusal(Self.response(401, Self.block("E9005"))), request.path)
            XCTAssertTrue(request.isCallerRefusal(Self.response(401, Self.block("E9051"))), request.path)
            XCTAssertFalse(request.isCallerRefusal(Self.response(401, Self.block("E1001"))), request.path)
            XCTAssertFalse(request.isCallerRefusal(Self.response(401, "")), request.path)
            XCTAssertFalse(request.isCallerRefusal(Self.response(400, Self.block("E9005"))), request.path)
        }
        XCTAssertFalse(requests[2].isCallerRefusal(Self.response(401, Self.block("E9005"))), "void")
    }

    // MARK: - Fixtures

    private static let request = PayInFixture.request(cardOnly: true)

    private static func payment(_ attempt: PayabliAttempt) -> PayabliPayInRequest {
        PayabliPayInRequest(
            paymentMethod: .stored(PayabliPayInPaymentMethod.Stored(method: .card, storedMethodId: "stored-1")),
            options: PayabliPayInRequestConfiguration(
                paymentDetails: PayabliPayInPaymentDetails(totalAmount: 12.34),
                paymentReference: "p1",
                attempt: attempt
            )
        )
    }

    private static let approved =
        #"{"code":"A0000","reason":"Approved","data":{"paymentTransId":"101-abc","authCode":"A1","referenceId":"r-1"}}"#

    private static func block(_ code: String) -> String {
        #"{"code":"\#(code)","reason":"Blocked","explanation":"The payer is blocked.","data":null}"#
    }

    private static func response(_ status: Int, _ body: String) -> PayabliResponse {
        PayabliResponse(statusCode: status, headers: [:], body: Data(body.utf8))
    }

    private static func client(over http: AnsweringTransport, tokens: CountingTokens) throws -> PayInPaymentFlowClient {
        let config = try PayabliConfig(entryPoint: "entry", environment: .sandbox, tokenProvider: { await tokens.next() })
        let auth = PayabliAuth(config: config)
        return PayInPaymentFlowClient(
            transport: AuthenticatedTransport(base: http, auth: auth, logger: PayabliLogger(category: .network))
        )
    }

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

/// Answers every request with one status and body, counting the sends.
private actor AnsweringTransport: PayabliTransport {
    private(set) var count = 0
    private let statusCode: Int
    private let body: String

    init(statusCode: Int, body: String) {
        self.statusCode = statusCode
        self.body = body
    }

    func perform(_: PayabliRequest) async throws -> PayabliResponse {
        PayabliSendMark.current?.set()
        count += 1
        return PayabliResponse(statusCode: statusCode, headers: [:], body: Data(body.utf8))
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding _: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        _ = try await perform(request)
        throw PayabliGenericError(type: .tokenExpired, reason: "not answered in this test")
    }
}

/// A new token on every call, counting how many the provider issued.
private actor CountingTokens {
    private(set) var issued = 0

    func next() -> String {
        issued += 1
        return "token-\(issued)"
    }
}

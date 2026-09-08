@testable import PayabliSDKCore
@testable import PayabliSDKPayInPaymentFlow
import XCTest

/// Every money-moving route carries an idempotency key, whether or not the caller supplied one.
///
/// Without one the service recognises no repeat, so a double submit or a retry is a second payment.
/// These cases drive the facade rather than the client, because reserving the key is the facade's job
/// and a client test cannot tell a reserved key from a caller's.
/// The fixtures both idempotency suites drive, so neither carries a copy of them.
@MainActor
enum PayInFixture {
    // MARK: - Support

    /// The parts of an interruption, or nil when the failure was classified as an answer.
    static func interruption(
        _ failure: any Error
    ) -> (code: PayabliErrorCode, causeType: String)? {
        guard
            case let .submissionInterrupted(code, causeType) =
            failure as? PayabliPayInPaymentFlowError
        else {
            return nil
        }
        return (code, causeType)
    }

    static func makeFlow(
        transport: any PayabliTransport,
        key: String
    ) -> PayabliPayInPaymentFlow {
        let flow = PayabliPayInPaymentFlow(
            accessToken: "token",
            entryPoint: "entry",
            environment: .sandbox,
            transport: transport
        )
        flow.newIdempotencyKey = { key }
        return flow
    }

    static func request(
        idempotencyKey: String?,
        cardOnly: Bool = false,
        totalAmount: Double = 12.34,
        orderId: String? = nil
    ) -> PayabliPayInPaymentFlowRequest {
        PayabliPayInPaymentFlowRequest(
            paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: totalAmount),
            paymentMethod: cardOnly
                ? .card(PayabliPayInPaymentFlowCardMethod(
                    data: PayabliPayInPaymentFlowCardData(
                        cardNumber: "4111 1111 1111 1111",
                        expiration: "02/27",
                        cardholderName: "John Cassian",
                        cvv: "999",
                        billingZip: "12345"
                    ),
                    saveIfSuccess: false
                ))
                : .stored(PayabliPayInPaymentFlowStoredMethod(method: .card, storedMethodId: "stored-1")),
            orderId: orderId,
            idempotencyKey: idempotencyKey
        )
    }

    /// Asserts the block threw and returns what it threw, so nothing below it is quietly skipped.
    static func failure(
        from block: () async throws -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> any Error {
        do {
            try await block()
            XCTFail("expected a failure, got a success", file: file, line: line)
            return PayabliGenericError(code: .unknown, reason: "no failure")
        } catch {
            return error
        }
    }

    static let approved = Data("""
    {"code":"A0000","reason":"Approved","responseData":{"authCode":"1","referenceId":"trans-1"}}
    """.utf8)

    static let declined = Data("""
    {"code":"D0001","reason":"Declined","explanation":"Declined by the issuer."}
    """.utf8)
}

final class RecordingIdempotencyTransport: PayabliTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String?] = []
    private let body: Data?
    private let status: Int
    private let failure: (any Error)?

    init(body: Data, status: Int = 200) {
        self.body = body
        self.status = status
        failure = nil
    }

    init(failure: any Error) {
        body = nil
        status = 200
        self.failure = failure
    }

    var sentKeys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded.compactMap { $0 }
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return recorded.count
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        lock.lock()
        recorded.append(request.headers["idempotencyKey"])
        lock.unlock()

        if let failure {
            throw failure
        }
        return PayabliResponse(statusCode: status, headers: [:], body: body ?? Data())
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        let response = try await perform(request)
        try mapPayabliHTTPError(response: response)
        return try decodePayabliV2Envelope(T.self, from: response)
    }
}

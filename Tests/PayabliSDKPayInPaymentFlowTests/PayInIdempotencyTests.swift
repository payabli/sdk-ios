@testable import PayabliSDKCore
@testable import PayabliSDKPayInPaymentFlow
import XCTest

/// Every money-moving route carries an idempotency key, whether or not the caller supplied one.
///
/// Without one the service recognises no repeat, so a double submit or a retry is a second payment.
/// These cases drive the facade rather than the client, because reserving the key is the facade's job
/// and a client test cannot tell a reserved key from a caller's.
@MainActor
final class PayInIdempotencyTests: XCTestCase {
    // MARK: - The key reaches the wire

    func testACaptureWithNoKeySuppliedStillSendsOne() async throws {
        let transport = RecordingIdempotencyTransport(body: Self.approved)
        let flow = Self.makeFlow(transport: transport, key: "reserved-1")

        _ = try await flow.capture(Self.request(idempotencyKey: nil))

        XCTAssertEqual(transport.sentKeys, ["reserved-1"])
    }

    func testACallersOwnKeyIsSentUnchanged() async throws {
        let transport = RecordingIdempotencyTransport(body: Self.approved)
        let flow = Self.makeFlow(transport: transport, key: "reserved-1")

        _ = try await flow.capture(Self.request(idempotencyKey: "caller-key"))

        XCTAssertEqual(transport.sentKeys, ["caller-key"], "a reserved key must not replace the caller's")
    }

    func testAnAuthorizationCarriesAKey() async throws {
        let transport = RecordingIdempotencyTransport(body: Self.approved)
        let flow = Self.makeFlow(transport: transport, key: "reserved-2")

        _ = try await flow.authorize(Self.request(idempotencyKey: nil, cardOnly: true))

        XCTAssertEqual(transport.sentKeys, ["reserved-2"])
    }

    /// The route that passed `nil` before this change, so a retried capture was a second capture.
    func testCapturingAnAuthorizationCarriesAKey() async throws {
        let transport = RecordingIdempotencyTransport(body: Self.approved)
        let flow = Self.makeFlow(transport: transport, key: "reserved-3")

        _ = try await flow.captureAuthorizedTransaction(
            PayabliPayInPaymentFlowAuthorizedRequest(
                transId: "trans-1",
                paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 10)
            )
        )

        XCTAssertEqual(transport.sentKeys, ["reserved-3"])
    }

    func testTwoAttemptsReserveTwoKeys() async throws {
        let transport = RecordingIdempotencyTransport(body: Self.approved)
        var minted = 0
        let flow = PayabliPayInPaymentFlow(
            accessToken: "token",
            entryPoint: "entry",
            environment: .sandbox,
            transport: transport,
            newIdempotencyKey: {
                minted += 1
                return "reserved-\(minted)"
            }
        )

        _ = try await flow.capture(Self.request(idempotencyKey: nil))
        _ = try await flow.capture(Self.request(idempotencyKey: nil))

        // A second payment is a second key. A retry the caller chooses is the caller's own key, which
        // is the case above.
        XCTAssertEqual(transport.sentKeys, ["reserved-1", "reserved-2"])
    }

    // MARK: - A key that cannot be sent is refused, not dropped

    func testABlankKeyIsRefusedAndNothingIsSent() async {
        let transport = RecordingIdempotencyTransport(body: Self.approved)
        let flow = Self.makeFlow(transport: transport, key: "reserved-1")

        let failure = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: " "))
        })

        // Dropping it silently is the defect: the request would go out with no duplicate protection
        // to a caller who set a key and believes it is protected.
        XCTAssertEqual(
            failure as? PayabliPayInPaymentFlowError,
            .invalidInput("The idempotency key cannot be blank.")
        )
        XCTAssertEqual(transport.count, 0, "nothing is sent")
    }

    func testAKeyThatCannotSitInAHeaderIsRefused() async {
        let transport = RecordingIdempotencyTransport(body: Self.approved)
        let flow = Self.makeFlow(transport: transport, key: "reserved-1")

        let failure = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: "key\r\nX-Injected: v"))
        })

        XCTAssertEqual(
            failure as? PayabliPayInPaymentFlowError,
            .invalidInput("The idempotency key may contain printable ASCII only.")
        )
        XCTAssertEqual(transport.count, 0, "nothing is sent")
    }

    // MARK: - Which failures report the key

    func testANetworkFailureReportsTheKeyThatWentOut() async {
        let transport = RecordingIdempotencyTransport(
            failure: PayabliGenericError(code: .networkError, reason: "Network request failed")
        )
        let flow = Self.makeFlow(transport: transport, key: "reserved-9")

        let failure = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: nil))
        })

        guard case let .submissionInterrupted(retryKey, _) = failure as? PayabliPayInPaymentFlowError else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertEqual(retryKey, "reserved-9")
    }

    func testAServerFailureReportsTheKey() async {
        let transport = RecordingIdempotencyTransport(body: Data("{}".utf8), status: 500)
        let flow = Self.makeFlow(transport: transport, key: "reserved-9")

        let failure = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: nil))
        })

        guard case let .submissionInterrupted(retryKey, _) = failure as? PayabliPayInPaymentFlowError else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertEqual(retryKey, "reserved-9")
    }

    /// A decline is an answer, so the outcome is known and a retry is a new payment.
    func testADeclineReportsNoKey() async {
        let transport = RecordingIdempotencyTransport(body: Self.declined)
        let flow = Self.makeFlow(transport: transport, key: "reserved-9")

        let failure = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: nil))
        })

        guard case .transactionFailed = failure as? PayabliPayInPaymentFlowError else {
            return XCTFail("expected transactionFailed, got \(failure)")
        }
    }

    /// A repeat the service recognised is what a key produces at all. Reporting it as unknown would
    /// tell a caller to resend the key that provoked it.
    func testARecognisedRepeatReportsNoKey() async {
        let transport = RecordingIdempotencyTransport(body: Data("{}".utf8), status: 409)
        let flow = Self.makeFlow(transport: transport, key: "reserved-9")

        let failure = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: nil))
        })

        XCTAssertNil(
            (failure as? PayabliPayInPaymentFlowError).flatMap { error -> String? in
                guard case let .submissionInterrupted(key, _) = error else { return nil }
                return key
            },
            "a 409 is an answer, not an open outcome"
        )
    }

    /// The store route carries no key, so no failure on it can report one.
    func testAStoreFailureReportsNoKey() async {
        let transport = RecordingIdempotencyTransport(
            failure: PayabliGenericError(code: .networkError, reason: "Network request failed")
        )
        let flow = Self.makeFlow(transport: transport, key: "reserved-9")

        let failure = await Self.failure(from: {
            _ = try await flow.addCard(
                PayabliPayInPaymentFlowCardData(
                    cardNumber: "4111 1111 1111 1111",
                    expiration: "02/27",
                    cardholderName: "John Cassian",
                    cvv: "999",
                    billingZip: "12345"
                ),
                options: PayabliPayInPaymentFlowTokenStorageOptions()
            )
        })

        guard case .submissionInterrupted = failure as? PayabliPayInPaymentFlowError else {
            XCTAssertEqual(transport.sentKeys, [], "the store route sends no key")
            return
        }
        XCTFail("a store failure must not report a retry key")
    }

    // MARK: - Support

    private static func makeFlow(
        transport: any PayabliTransport,
        key: String
    ) -> PayabliPayInPaymentFlow {
        PayabliPayInPaymentFlow(
            accessToken: "token",
            entryPoint: "entry",
            environment: .sandbox,
            transport: transport,
            newIdempotencyKey: { key }
        )
    }

    private static func request(
        idempotencyKey: String?,
        cardOnly: Bool = false
    ) -> PayabliPayInPaymentFlowRequest {
        PayabliPayInPaymentFlowRequest(
            paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 12.34),
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
            idempotencyKey: idempotencyKey
        )
    }

    /// Asserts the block threw and returns what it threw, so nothing below it is quietly skipped.
    private static func failure(
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

    private static let approved = Data("""
    {"code":"A0000","reason":"Approved","responseData":{"authCode":"1","referenceId":"trans-1"}}
    """.utf8)

    private static let declined = Data("""
    {"code":"D0001","reason":"Declined","explanation":"Declined by the issuer."}
    """.utf8)
}

/// Records the idempotency key of every request that reached the network.
private final class RecordingIdempotencyTransport: PayabliTransport, @unchecked Sendable {
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

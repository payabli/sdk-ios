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
            transport: transport
        )
        flow.newIdempotencyKey = {
            minted += 1
            return "reserved-\(minted)"
        }

        _ = try await flow.capture(Self.request(idempotencyKey: nil))
        _ = try await flow.capture(Self.request(idempotencyKey: nil))

        // A second payment is a second key. A retry the caller chooses is the caller's own key, which
        // is the case above.
        XCTAssertEqual(transport.sentKeys, ["reserved-1", "reserved-2"])
    }

    // MARK: - An attempt nobody knows the outcome of keeps its key

    /// The case the key exists for. An attempt that was interrupted may already have taken the money,
    /// so the submit after it has to be the same request rather than a new one: the service refuses a
    /// repeat, where a fresh key takes the money again. A payer pressing Submit a second time is the
    /// ordinary way this happens.
    func testARetryAfterAnUnknownOutcomeSendsTheSameKey() async {
        let transport = SequencedIdempotencyTransport(
            outcomes: [
                .failure(PayabliGenericError(code: .networkError, reason: "Network request failed")),
                .success(Self.approved)
            ]
        )
        let flow = Self.makeFlow(transport: transport, keys: ["reserved-1", "reserved-2"])

        _ = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: nil))
        })
        _ = try? await flow.capture(Self.request(idempotencyKey: nil))

        XCTAssertEqual(
            transport.sentKeys,
            ["reserved-1", "reserved-1"],
            "the retry has to be the same request, or the payer is charged twice"
        )
    }

    /// A different payment is not that retry. Reusing the key there would have the service refuse a
    /// payment the payer meant to make.
    func testADifferentAmountAfterAnUnknownOutcomeSendsANewKey() async {
        let transport = SequencedIdempotencyTransport(
            outcomes: [
                .failure(PayabliGenericError(code: .networkError, reason: "Network request failed")),
                .success(Self.approved)
            ]
        )
        let flow = Self.makeFlow(transport: transport, keys: ["reserved-1", "reserved-2"])

        _ = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: nil))
        })
        _ = try? await flow.capture(Self.request(idempotencyKey: nil, totalAmount: 99.99))

        XCTAssertEqual(transport.sentKeys, ["reserved-1", "reserved-2"])
    }

    /// An answer settles the attempt, so the next submit is a new payment and carries a new key.
    func testASubmitAfterAKnownOutcomeSendsANewKey() async {
        let transport = SequencedIdempotencyTransport(
            outcomes: [.success(Self.declined), .success(Self.approved)]
        )
        let flow = Self.makeFlow(transport: transport, keys: ["reserved-1", "reserved-2"])

        _ = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: nil))
        })
        _ = try? await flow.capture(Self.request(idempotencyKey: nil))

        XCTAssertEqual(
            transport.sentKeys,
            ["reserved-1", "reserved-2"],
            "a refusal is an answer, so the next submit is a second payment"
        )
    }

    /// A caller that supplies its own key is never given the held one.
    func testACallersKeyIsSentEvenAfterAnUnknownOutcome() async {
        let transport = SequencedIdempotencyTransport(
            outcomes: [
                .failure(PayabliGenericError(code: .networkError, reason: "Network request failed")),
                .success(Self.approved)
            ]
        )
        let flow = Self.makeFlow(transport: transport, keys: ["reserved-1", "reserved-2"])

        _ = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: nil))
        })
        _ = try? await flow.capture(Self.request(idempotencyKey: "caller-key"))

        XCTAssertEqual(transport.sentKeys, ["reserved-1", "caller-key"])
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

    /// The key reported is the one the request carried, not the one the caller wrote.
    ///
    /// `sendableKey` normalises before the header is set, so a caller value with surrounding space is
    /// sent trimmed. Reporting the untrimmed value would name a key that never went over the wire.
    func testTheReportedKeyIsTheKeyThatWentOnTheWire() async {
        let transport = RecordingIdempotencyTransport(
            failure: PayabliGenericError(code: .networkError, reason: "Network request failed")
        )
        let flow = Self.makeFlow(transport: transport, key: "unused")

        let failure = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: "  caller-key  "))
        })

        XCTAssertEqual(transport.sentKeys, ["caller-key"])
        guard case let .submissionInterrupted(retryKey, _, _) = failure as? PayabliPayInPaymentFlowError
        else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertEqual(retryKey, "caller-key")
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

        guard
            case let .submissionInterrupted(retryKey, code, causeType) =
            failure as? PayabliPayInPaymentFlowError
        else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertEqual(retryKey, "reserved-9")
        XCTAssertEqual(code, .networkError)
        // The failing type and none of its message: that message can name a host or quote a body.
        XCTAssertEqual(causeType, "PayabliSDKCore.PayabliGenericError")
    }

    /// A 5xx whose body carries a message decodes into a failure rather than reaching the typed server
    /// error, and that is the path a real 5xx takes. A bodyless `{}` bypasses it, which is what made an
    /// earlier version of this case pass without exercising the classification at all.
    func testAServerFailureReportsTheKey() async {
        let transport = RecordingIdempotencyTransport(
            body: Data(#"{"message":"Internal Server Error"}"#.utf8),
            status: 500
        )
        let flow = Self.makeFlow(transport: transport, key: "reserved-9")

        let failure = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: nil))
        })

        guard let interrupted = Self.interruption(failure) else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertEqual(interrupted.retryKey, "reserved-9")
        XCTAssertEqual(interrupted.code, .serverError)
    }

    /// The same status with an empty body, which the status mapping answers rather than the decoder.
    /// Both shapes have to publish the same classification: a caller branching on the code would
    /// otherwise see a server failure only when the service happened to send a message with it.
    func testABodylessServerFailureReportsTheSameCode() async {
        let transport = RecordingIdempotencyTransport(body: Data(), status: 500)
        let flow = Self.makeFlow(transport: transport, key: "reserved-9")

        let failure = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: nil))
        })

        guard let interrupted = Self.interruption(failure) else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertEqual(interrupted.retryKey, "reserved-9")
        XCTAssertEqual(interrupted.code, .serverError)
    }

    /// Cancelled while in flight, so whether the service acted on it is exactly what nobody knows.
    func testACancellationReportsTheKey() async {
        let transport = RecordingIdempotencyTransport(
            failure: PayabliGenericError(code: .userCancelled, reason: "Cancelled")
        )
        let flow = Self.makeFlow(transport: transport, key: "reserved-9")

        let failure = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: nil))
        })

        guard let interrupted = Self.interruption(failure) else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertEqual(interrupted.retryKey, "reserved-9")
        XCTAssertEqual(interrupted.code, .userCancelled)
    }

    /// An answer the SDK cannot read is the case the key exists for: the payment may well have been
    /// taken, and the only record of it is on the service.
    func testAnUnreadableAnswerReportsTheKey() async {
        let transport = RecordingIdempotencyTransport(body: Data("not json".utf8))
        let flow = Self.makeFlow(transport: transport, key: "reserved-9")

        let failure = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: nil))
        })

        guard let interrupted = Self.interruption(failure) else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertEqual(interrupted.retryKey, "reserved-9")
        XCTAssertEqual(interrupted.code, .decodingError)
    }

    /// A decline is an answer, so the outcome is known and a retry is a new payment. It arrives on a
    /// successful status with the refusal in the body, which is why the response code decides and not
    /// the status.
    func testADeclineReportsNoKey() async {
        let transport = RecordingIdempotencyTransport(body: Self.declined)
        let flow = Self.makeFlow(transport: transport, key: "reserved-9")

        let failure = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: nil))
        })

        guard case .transactionFailed = failure as? PayabliPayInPaymentFlowError else {
            return XCTFail("expected transactionFailed, got \(failure)")
        }
        XCTAssertEqual((failure as? any PayabliError)?.code, .paymentDeclined)
        XCTAssertNil(Self.interruption(failure), "a refusal settles the outcome")
    }

    /// The same successful status carrying a code that is not a refusal: the service could not process
    /// the request rather than declining it, so whether the payment was taken is exactly what is not
    /// known. The sibling separates these two the same way.
    func testAServiceFailureOnASuccessfulStatusReportsTheKey() async {
        let transport = RecordingIdempotencyTransport(
            body: Data(#"{"code":"E0001","reason":"Unable to process","explanation":"Try again."}"#.utf8)
        )
        let flow = Self.makeFlow(transport: transport, key: "reserved-9")

        let failure = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: nil))
        })

        guard let interrupted = Self.interruption(failure) else {
            return XCTFail("expected submissionInterrupted, got \(failure)")
        }
        XCTAssertEqual(interrupted.retryKey, "reserved-9")
        XCTAssertEqual(interrupted.code, .serverError)
    }

    /// A repeat the service recognised is what a key produces at all. Reporting it as unknown would
    /// tell a caller to resend the key that provoked it.
    func testARecognisedRepeatReportsNoKey() async {
        let transport = RecordingIdempotencyTransport(
            body: Data(#"{"message":"Duplicate request"}"#.utf8),
            status: 409
        )
        let flow = Self.makeFlow(transport: transport, key: "reserved-9")

        let failure = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: nil))
        })

        XCTAssertNil(
            (failure as? PayabliPayInPaymentFlowError).flatMap { error -> String? in
                guard case let .submissionInterrupted(key, _, _) = error else { return nil }
                return key
            },
            "a 409 is an answer, not an open outcome"
        )
    }

    /// The same repeat with no body at all, which is the shape the status mapping answers rather than
    /// the decoder. Reporting it as open tells a caller to resend the key the service refuses.
    func testABodylessRecognisedRepeatReportsNoKey() async {
        let transport = RecordingIdempotencyTransport(body: Data(), status: 409)
        let flow = Self.makeFlow(transport: transport, key: "reserved-9")

        let failure = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: nil))
        })

        XCTAssertEqual((failure as? any PayabliError)?.code, .conflict)
        XCTAssertNil(
            (failure as? PayabliPayInPaymentFlowError).flatMap { error -> String? in
                guard case let .submissionInterrupted(key, _, _) = error else { return nil }
                return key
            },
            "the service already holds the request, so the outcome is settled"
        )
    }

    /// A decline with no body, which the status mapping answers. Still an answer, so still no key.
    func testABodylessDeclineReportsNoKey() async {
        let transport = RecordingIdempotencyTransport(body: Data(), status: 402)
        let flow = Self.makeFlow(transport: transport, key: "reserved-9")

        let failure = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: nil))
        })

        XCTAssertEqual((failure as? any PayabliError)?.code, .paymentDeclined)
        XCTAssertNil(Self.interruption(failure), "a decline is an answer, whatever its body")
    }

    /// Refused before the service acted on it, so nothing was taken and the next submit is a fresh
    /// attempt rather than a repeat of this one.
    func testARefusalForTooManyRequestsReportsNoKey() async {
        let transport = RecordingIdempotencyTransport(body: Data(), status: 429)
        let flow = Self.makeFlow(transport: transport, key: "reserved-9")

        let failure = await Self.failure(from: {
            _ = try await flow.capture(Self.request(idempotencyKey: nil))
        })

        XCTAssertEqual((failure as? any PayabliError)?.code, .rateLimited)
        XCTAssertNil(Self.interruption(failure), "the request was refused, not attempted")
    }

    /// A refused credential never reached the operation, so no payment was attempted and no key is
    /// reported. Each of these arrives carrying a message, which is the shape that reaches the body
    /// decoder rather than the status mapping, and the classification has to be the same either way.
    func testARefusedCredentialReportsNoKeyWhateverItsBody() async {
        let expected: [Int: PayabliErrorCode] = [
            401: .tokenExpired,
            403: .permissionDenied,
            410: .sessionBurned
        ]

        for (status, code) in expected {
            let transport = RecordingIdempotencyTransport(
                body: Data(#"{"message":"Refused"}"#.utf8),
                status: status
            )
            let flow = Self.makeFlow(transport: transport, key: "reserved-9")

            let failure = await Self.failure(from: {
                _ = try await flow.capture(Self.request(idempotencyKey: nil))
            })

            XCTAssertEqual(
                (failure as? any PayabliError)?.code,
                code,
                "a \(status) carrying a message must classify as it does with none"
            )
            XCTAssertNil(
                Self.interruption(failure),
                "a \(status) never reached the operation, so there is nothing to retry"
            )
        }
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

    /// The parts of an interruption, or nil when the failure was classified as an answer.
    private static func interruption(
        _ failure: any Error
    ) -> (retryKey: String, code: PayabliErrorCode, causeType: String)? {
        guard
            case let .submissionInterrupted(retryKey, code, causeType) =
            failure as? PayabliPayInPaymentFlowError
        else {
            return nil
        }
        return (retryKey, code, causeType)
    }

    private static func makeFlow(
        transport: any PayabliTransport,
        keys: [String]
    ) -> PayabliPayInPaymentFlow {
        let flow = PayabliPayInPaymentFlow(
            accessToken: "token",
            entryPoint: "entry",
            environment: .sandbox,
            transport: transport
        )
        let remaining = MintedKeys(keys)
        flow.newIdempotencyKey = { remaining.next() }
        return flow
    }

    private static func makeFlow(
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

    private static func request(
        idempotencyKey: String?,
        cardOnly: Bool = false,
        totalAmount: Double = 12.34
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

/// Hands out the keys a test named, in order, so a second attempt is distinguishable from the first.
private final class MintedKeys: @unchecked Sendable {
    private let lock = NSLock()
    private var remaining: [String]

    init(_ keys: [String]) {
        remaining = keys
    }

    func next() -> String {
        lock.lock()
        defer { lock.unlock() }
        return remaining.isEmpty ? "exhausted" : remaining.removeFirst()
    }
}

/// One outcome per call, so a test can fail an attempt and then answer the retry.
private final class SequencedIdempotencyTransport: PayabliTransport, @unchecked Sendable {
    enum Outcome {
        case success(Data)
        case failure(any Error)
    }

    private let lock = NSLock()
    private var recorded: [String?] = []
    private var outcomes: [Outcome]

    init(outcomes: [Outcome]) {
        self.outcomes = outcomes
    }

    var sentKeys: [String] {
        lock.lock()
        defer { lock.unlock() }
        return recorded.compactMap { $0 }
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        lock.lock()
        recorded.append(request.headers["idempotencyKey"])
        let outcome = outcomes.isEmpty ? Outcome.success(Data()) : outcomes.removeFirst()
        lock.unlock()

        switch outcome {
        case let .success(body):
            return PayabliResponse(statusCode: 200, headers: [:], body: body)
        case let .failure(error):
            throw error
        }
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

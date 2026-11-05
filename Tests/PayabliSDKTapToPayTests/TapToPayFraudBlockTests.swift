import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// A payer blocked by fraud control at the opening: the payment is not opened, whatever the status, and nothing else
/// is asked.
@available(iOS 16.7, *)
@MainActor
final class TapToPayFraudBlockTests: XCTestCase {
    private let wire = FraudWire()

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = wire.handler
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testAnOpeningBlockedByFraudControlIsNotOpenedAtItsStatusAndCode() async throws {
        for status in [400, 401] {
            for code in ["E9005", "E9051"] {
                let (ttp, provider, tokens) = try await makeReadyTTP()
                let issued = tokens.value
                wire.reset(initiate: [(status, Self.block(code)), (200, Self.opened)])

                let failure = try await chargeFailure(ttp)

                let label = "\(status) \(code)"
                XCTAssertEqual(failure.type, .paymentNotOpened, "\(label): \(failure)")
                XCTAssertEqual(failure.httpStatus, status, label)
                XCTAssertEqual(failure.rawCode, code, label)
                XCTAssertEqual(wire.initiateKeys.count, 1, "\(label): no replay")
                XCTAssertEqual(tokens.value, issued, "\(label): the provider is not asked")
                XCTAssertEqual(provider.startReadingCalls, 0, "\(label): the reader is not asked")
                XCTAssertEqual(ttp.sessionState, .ready, "\(label): the session is untouched")

                _ = try await ttp.charge(paymentDetails: Self.details, attempt: .retry)
                XCTAssertEqual(wire.initiateKeys.count, 2, label)
                XCTAssertNotEqual(wire.initiateKeys[0], wire.initiateKeys[1], "\(label): the key was released")
            }
        }
    }

    func testAFraudBlockOnAResentKeyKeepsTheKeyHeldAndTheCaptureUnknown() async throws {
        let (ttp, provider, _) = try await makeReadyTTP()
        provider.readingResult = Self.read(.indeterminate)
        wire.reset(initiate: [(200, Self.opened), (400, Self.block("E9005"))])
        _ = try? await ttp.charge(paymentDetails: Self.details)
        provider.readingResult = Self.read(.approved)

        let blocked: TapToPayError
        do {
            _ = try await ttp.charge(paymentDetails: Self.details, attempt: .retry)
            return XCTFail("expected the retry to be blocked")
        } catch let failure as TapToPayError {
            blocked = failure
        }
        _ = try await ttp.charge(paymentDetails: Self.details, attempt: .retry)

        XCTAssertEqual(blocked.type, .paymentNotOpened, "\(blocked)")
        XCTAssertEqual(blocked.code, 3019)
        XCTAssertEqual(blocked.capture, .unknown)
        XCTAssertEqual(wire.initiateKeys.count, 3)
        XCTAssertEqual(Set(wire.initiateKeys).count, 1, "every attempt sent the held key: \(wire.initiateKeys)")
    }

    func testAnOpeningAnswered401WithAnyOtherBodyStillRefreshesAndReplays() async throws {
        let (ttp, _, tokens) = try await makeReadyTTP()
        let issued = tokens.value
        wire.reset(initiate: [(401, Self.block("E1001")), (200, Self.opened)])

        _ = try await ttp.charge(paymentDetails: Self.details)

        XCTAssertEqual(wire.initiateKeys.count, 2, "the opening and its replay")
        XCTAssertGreaterThan(tokens.value, issued, "the provider is asked for a new token")
    }

    func testAnyOtherBadRequestOnTheOpeningIsNotAFraudBlock() async throws {
        let (ttp, _, _) = try await makeReadyTTP()
        wire.reset(initiate: [(400, Self.block("E1001"))])

        let failure = try await chargeFailure(ttp)

        XCTAssertNotEqual(failure.type, .paymentNotOpened, "\(failure)")
        XCTAssertEqual(failure.httpStatus, 400)
        XCTAssertEqual(failure.rawCode, "E1001")
    }

    // MARK: - Fixtures

    private static let details = PayabliTTPPaymentDetails(amount: 1, currency: "USD")
    private static let opened = #"{"code":"A01","data":{"paymentTransId":"ttp-txn-1"}}"#

    private static func read(_ outcome: CardReadOutcome) -> Result<CardReadResult, Error> {
        .success(CardReadResult(provider: "mock", encryptedPayload: Data(), outcome: outcome))
    }

    private static func block(_ code: String) -> String {
        #"{"code":"\#(code)","reason":"Blocked","explanation":"The payer is blocked.","data":null}"#
    }

    private func makeReadyTTP() async throws -> (PayabliTTP, MockTapToPayProvider, TokenCount) {
        wire.reset(initiate: [])
        let provider = MockTapToPayProvider()
        let tokens = TokenCount()
        let config = try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { tokens.next() })
        let ttp = PayabliTTP(
            config: config,
            provider: provider,
            attestation: MockDeviceAttestationService(),
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
        try await ttp.initialize()
        XCTAssertEqual(ttp.sessionState, .ready, "the fixture itself is broken if this fails")
        return (ttp, provider, tokens)
    }

    private func chargeFailure(_ ttp: PayabliTTP) async throws -> TapToPayError {
        do {
            _ = try await ttp.charge(paymentDetails: Self.details)
        } catch let failure as TapToPayError {
            return failure
        }
        XCTFail("expected the charge to fail")
        throw CancellationError()
    }
}

/// Answers each opening with the next scripted answer, and every other route as a ready session and an approved
/// close; records the key each opening sent.
private final class FraudWire: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [(Int, String)] = []
    private var keys: [String] = []

    var initiateKeys: [String] {
        lock.withLock { keys }
    }

    func reset(initiate: [(Int, String)]) {
        lock.withLock {
            answers = initiate
            keys = []
        }
    }

    var handler: StubURLProtocol.Handler {
        { [self] request in
            let path = request.url?.path ?? ""
            let (status, body): (Int, String)
            if path.contains("/MoneyIn/initiate") {
                (status, body) = lock.withLock {
                    keys.append(request.value(forHTTPHeaderField: payabliIdempotencyKeyHeader) ?? "")
                    return answers.isEmpty ? (200, #"{"code":"A01","data":{"paymentTransId":"ttp-txn-1"}}"#)
                        : answers.removeFirst()
                }
            } else if path.contains("/MoneyIn/update/") {
                (status, body) = (200, #"{"code":"A01","data":{"paymentTransId":"ttp-txn-1"}}"#)
            } else {
                (status, body) = (200, """
                {"responseCode":1,"isSuccess":true,"paymentToken":"payment_tok",
                 "responseData":{"credentials":{"secretKey":"s","apiKey":"a","merchantId":"m","terminalId":"t"}}}
                """)
            }
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: status,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!,
                Data(body.utf8)
            )
        }
    }
}

/// A new token on every call, counting how many the provider issued.
private final class TokenCount: @unchecked Sendable {
    private let lock = NSLock()
    private var issued = 0

    var value: Int {
        lock.withLock { issued }
    }

    func next() -> String {
        lock.withLock {
            issued += 1
            return "token-\(issued)"
        }
    }
}

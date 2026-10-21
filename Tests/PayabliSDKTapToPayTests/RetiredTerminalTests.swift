@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// A terminal belongs to the session it was built from. Once that session is replaced or ended, the terminal refuses
/// setup, repair, activation and a new charge with 1019 before the reader is touched, and lands `.failed(.sessionEnded)`.
@available(iOS 16.7, *)
@MainActor
final class RetiredTerminalTests: XCTestCase {
    private static let paymentTransId = "TXN-RETIRED"
    private static let reason = "the session this was created with was replaced or ended; create a new one"

    override func tearDown() {
        StubURLProtocol.handler = nil
        PayabliSession.resetForTesting()
        super.tearDown()
    }

    func testARetiredTerminalRefusesInitializeBeforeTheReaderIsTouched() async throws {
        let (ttp, provider, attestation, _) = try makeTTP(live: false)

        let refusal = await failure { try await ttp.initialize() }

        assertRetired(refusal, on: ttp)
        XCTAssertEqual(attestation.attestCalls, 0, "nothing was sent")
        XCTAssertEqual(provider.configureCalls, 0)
        XCTAssertEqual(provider.prepareReaderCalls, 0)
    }

    func testAReplacementLandingWhileTheRunAttestsStopsItBeforeTheReaderIsConfigured() async throws {
        let requests = Requests()
        StubURLProtocol.handler = requests.handler(paymentTransId: Self.paymentTransId)
        let provider = MockTapToPayProvider()
        let attestation = MockDeviceAttestationService()
        // Live until the run attests: the replacement lands while it does.
        let ttp = try PayabliTTP(
            config: PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" }),
            provider: provider,
            attestation: attestation,
            session: StubURLProtocol.makeSession(),
            isLive: { attestation.attestCalls == 0 }
        )

        let refusal = await failure { try await ttp.initialize() }

        assertRetired(refusal, on: ttp)
        XCTAssertEqual(attestation.attestCalls, 1)
        XCTAssertEqual(provider.configureCalls, 0)
        XCTAssertEqual(provider.prepareReaderCalls, 0)
    }

    func testARetiredTerminalRefusesAChargeOpeningNothingAndLeavingTheReaderAlone() async throws {
        let live = LiveFlag()
        let (ttp, provider, _, requests) = try makeTTP(live: live)
        try await ttp.initialize()
        let sentBefore = requests.count
        live.value = false

        let refusal = await failure { _ = try await self.charge(ttp) }

        assertRetired(refusal, on: ttp)
        XCTAssertEqual(requests.count, sentBefore, "nothing was opened")
        XCTAssertEqual(provider.startReadingCalls, 0)
    }

    func testARetiredTerminalRefusesActivation() async throws {
        let live = LiveFlag()
        let (ttp, _, attestation, _) = try makeTTP(live: live)
        attestation.pendingRegistration = "act-1"
        _ = await failure { try await ttp.initialize() }
        XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "act-1"), "the fixture itself is broken")
        live.value = false

        let refusal = await failure { try await ttp.activateDevice(activationCode: "123456") }

        assertRetired(refusal, on: ttp)
        XCTAssertEqual(attestation.activateCalls, 0)
    }

    func testAReadUnderWayWhenItsSessionIsReplacedFinishesAndItsCloseIsRefusedBeforeSending() async throws {
        let live = LiveFlag()
        let (ttp, provider, _, requests) = try makeTTP(live: live)
        try await ttp.initialize()
        provider.whileReading = { [session = ttp.session] in
            await session.auth.finish(with: PayabliGenericError(type: .tokenExpired, reason: "finished"))
            live.value = false
        }

        let refusal = await failure { _ = try await self.charge(ttp) }

        let error = refusal as? TapToPayError
        XCTAssertEqual(error?.type, .paymentNotClosed)
        XCTAssertEqual(error?.paymentTransId, Self.paymentTransId)
        XCTAssertEqual(provider.startReadingCalls, 1, "the read ran to its end")
        XCTAssertEqual(requests.updates, 0, "the close was refused before it was sent")
    }

    func testAnInstalledSessionsTerminalIsLiveAndAReplacedOnesIsNot() async throws {
        StubURLProtocol.handler = { request in
            (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)!, Data())
        }
        let config = try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { UUID().uuidString })
        let first = try PayabliSession.install(
            config: config,
            urlSession: StubURLProtocol.makeSession(),
            telemetryTransport: InMemoryTelemetryTransport()
        )
        let terminal = PayabliTTP(session: first, provider: MockTapToPayProvider(), attestation: MockDeviceAttestationService())
        XCTAssertTrue(terminal.isLive())

        _ = try? await first.transport.perform(PayabliRequest(method: .get, path: "/api/v2/ping"))
        XCTAssertTrue(terminal.isLive(), "a finished session is still the installed one")
        _ = try PayabliSession.install(
            config: config,
            urlSession: StubURLProtocol.makeSession(),
            telemetryTransport: InMemoryTelemetryTransport()
        )

        XCTAssertFalse(terminal.isLive())
    }

    // MARK: - Helpers

    private func assertRetired(_ refusal: any Error, on ttp: PayabliTTP, line: UInt = #line) {
        let error = refusal as? any PayabliError
        XCTAssertEqual(error?.type, .sessionNotInitialized, line: line)
        XCTAssertEqual(error?.code, 1019, line: line)
        XCTAssertEqual(error?.reason, Self.reason, line: line)
        XCTAssertEqual(ttp.sessionState, .failed(reason: .sessionEnded), line: line)
    }

    private func makeTTP(
        live: Bool
    ) throws -> (PayabliTTP, MockTapToPayProvider, MockDeviceAttestationService, Requests) {
        let flag = LiveFlag()
        flag.value = live
        return try makeTTP(live: flag)
    }

    private func makeTTP(
        live: LiveFlag
    ) throws -> (PayabliTTP, MockTapToPayProvider, MockDeviceAttestationService, Requests) {
        let requests = Requests()
        StubURLProtocol.handler = requests.handler(paymentTransId: Self.paymentTransId)
        let provider = MockTapToPayProvider()
        let attestation = MockDeviceAttestationService()
        let ttp = try PayabliTTP(
            config: PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" }),
            provider: provider,
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession(),
            isLive: { live.value }
        )
        return (ttp, provider, attestation, requests)
    }

    private func charge(_ ttp: PayabliTTP) async throws -> TransactionResult {
        try await ttp.charge(type: .sale, paymentDetails: PayabliTTPPaymentDetails(amount: 1, currency: "USD"))
    }

    private func failure(_ block: () async throws -> Void) async -> any Error {
        do {
            try await block()
            XCTFail("expected a failure, got a success")
            return PayabliGenericError(type: .unknown, reason: "no failure")
        } catch {
            return error
        }
    }
}

/// Whether a terminal's session is still the installed one, as a test sets it.
private final class LiveFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = true

    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Answers the routes a setup and a charge reach, and counts what was sent.
private final class Requests: @unchecked Sendable {
    private let lock = NSLock()
    private var sent = 0
    private var closes = 0

    var count: Int {
        lock.withLock { sent }
    }

    var updates: Int {
        lock.withLock { closes }
    }

    func handler(paymentTransId: String) -> StubURLProtocol.Handler {
        { [self] request in
            let path = request.url?.path ?? ""
            lock.withLock {
                sent += 1
                if path.contains("/MoneyIn/update/") {
                    closes += 1
                }
            }
            let body: [String: Any] = if path.contains("/MoneyIn/") {
                ["code": "A01", "data": ["paymentTransId": paymentTransId]]
            } else {
                [
                    "responseCode": 1,
                    "isSuccess": true,
                    "responseData": [
                        "credentials": ["secretKey": "s", "apiKey": "a", "merchantId": "m", "terminalId": "t"]
                    ],
                    "paymentToken": "payment_tok"
                ]
            }
            let data = try JSONSerialization.data(withJSONObject: body)
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!,
                data
            )
        }
    }
}

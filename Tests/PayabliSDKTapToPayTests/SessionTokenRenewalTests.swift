import Combine
@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// When a device route refuses a session sequence's token, the sequence renews it and reruns from its first call, a
/// single time: `initialize()`, the activation, and the repair a charge runs first. The first refusal lands nowhere, a
/// second reaches the caller as 1002, and a binding the service no longer holds is not renewed at all.
@available(iOS 16.7, *)
@MainActor
final class SessionTokenRenewalTests: XCTestCase {
    private var stub = RenewalStub()
    private var tokens = TokenCalls()

    override func setUp() {
        super.setUp()
        stub = RenewalStub()
        tokens = TokenCalls()
        StubURLProtocol.handler = stub.handle
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - initialize()

    func testARefusedTokenOnConfigIsRenewedAndTheWarmStartReachesReady() async throws {
        let (ttp, _, attestation, _) = try makeTTP()
        attestation.isAlreadyAttested = true
        stub.configStatuses = [401]

        try await ttp.initialize()

        XCTAssertEqual(ttp.sessionState, .ready)
        XCTAssertEqual(stub.configBearers, ["seed", "renewed-2"], "the second config carried a renewed token")
        XCTAssertEqual(tokens.count, 2, "one renewal")
        XCTAssertEqual(attestation.assertionCalls, 2, "the sequence ran again rather than the request being replayed")
    }

    func testARefusedTokenOnTheFirstColdCallIsRenewedAndTheRunStartsAgainFromThatCall() async throws {
        let (ttp, _, attestation, _) = try makeTTP()
        attestation.attestFailuresFirst = [PinnedTokenRefusal()]

        try await ttp.initialize()

        XCTAssertEqual(ttp.sessionState, .ready)
        XCTAssertEqual(attestation.attestCalls, 2, "the run started again from the attestation")
        XCTAssertEqual(stub.configBearers.count, 1)
    }

    func testTheFirstRefusalLandsNowhereBeforeTheRenewal() async throws {
        let (ttp, _, attestation, _) = try makeTTP()
        attestation.isAlreadyAttested = true
        stub.configStatuses = [401]
        var seen: [PayabliTTPSessionState] = []
        let watching = ttp.$sessionState.sink { seen.append($0) }

        try await ttp.initialize()
        watching.cancel()

        XCTAssertFalse(seen.contains {
            if case .failed = $0 {
                true
            } else {
                false
            }
        }, "\(seen)")
        XCTAssertEqual(seen.last, .ready)
    }

    func testASecondRefusalReportsAnExpiredTokenAndIsNotRenewedAgain() async throws {
        let (ttp, _, attestation, _) = try makeTTP()
        attestation.isAlreadyAttested = true
        stub.configStatuses = [401, 401]

        let failure = await failure { try await ttp.initialize() }

        XCTAssertEqual((failure as? any PayabliError)?.code, 1002, "got \(failure)")
        XCTAssertEqual(ttp.sessionState, .failed(reason: .serviceUnavailable))
        XCTAssertEqual(stub.configBearers.count, 2)
        XCTAssertEqual(tokens.count, 2, "renewed once only")
    }

    func testAFailureThatIsNotARefusedTokenIsNotRenewed() async throws {
        let (ttp, _, attestation, _) = try makeTTP()
        attestation.isAlreadyAttested = true
        stub.configStatuses = [500]

        _ = await failure { try await ttp.initialize() }

        XCTAssertEqual(stub.configBearers.count, 1)
        XCTAssertEqual(tokens.count, 1)
    }

    func testARenewalThatFailsReachesTheCallerAndNothingIsSentAgain() async throws {
        let (ttp, _, attestation, _) = try makeTTP(renewalFails: true)
        attestation.isAlreadyAttested = true
        stub.configStatuses = [401]

        let failure = await failure { try await ttp.initialize() }

        XCTAssertEqual((failure as? any PayabliError)?.type, .tokenProviderFailed, "got \(failure)")
        XCTAssertEqual(stub.configBearers.count, 1)
        XCTAssertNotEqual(ttp.sessionState, .fetchingConfig, "a failed renewal lands")
    }

    func testABindingTheServiceNoLongerHoldsOnConfigAsksForSetupAgainAndIsNotRenewed() async throws {
        let (ttp, _, attestation, _) = try makeTTP()
        attestation.isAlreadyAttested = true
        stub.configStatuses = [401]
        stub.configRefusalText = BindingRefusal.text

        let failure = await failure { try await ttp.initialize() }

        XCTAssertEqual((failure as? any PayabliError)?.code, 3005, "got \(failure)")
        XCTAssertEqual(ttp.sessionState, .failed(reason: .deviceSetupRequired))
        XCTAssertFalse(attestation.isAlreadyAttested, "the binding the service no longer holds was kept")
        XCTAssertEqual(tokens.count, 1, "nothing was renewed")
    }

    /// A phase that lands the session itself and throws something that would land elsewhere keeps its own landing:
    /// a registration that changed during the renewed `/config` is asked again, never read as a rejected configuration.
    func testAFailureAfterTheRenewalKeepsTheStateItsPhaseLandedOn() async throws {
        let (ttp, _, attestation, _) = try makeTTP()
        attestation.isAlreadyAttested = true
        stub.configStatuses = [401, 403]
        stub.onConfig = { call in
            if call == 2 {
                attestation.isAlreadyAttested = false
            }
        }

        _ = await failure { try await ttp.initialize() }

        XCTAssertEqual(ttp.sessionState, .failed(reason: .serviceUnavailable))
    }

    // MARK: - The repair a charge runs first

    func testARefusedTokenOnARepairIsRenewedAndTheRepairReachesReady() async throws {
        let ttp = try await makeExpiredTTP()
        stub.configStatuses = [401]

        try await ttp.reinitialize()

        XCTAssertEqual(ttp.sessionState, .ready)
        XCTAssertEqual(stub.configBearers.count, 3)
    }

    func testASecondRefusalOnARepairReportsAnExpiredToken() async throws {
        let ttp = try await makeExpiredTTP()
        stub.configStatuses = [401, 401]

        let failure = await failure { try await ttp.reinitialize() }

        XCTAssertEqual((failure as? any PayabliError)?.code, 1002, "got \(failure)")
        XCTAssertEqual(stub.configBearers.count, 3)
    }

    func testAChargeOnAnExpiredSessionRenewsATokenItsRepairWasRefusedAndGoesAhead() async throws {
        let ttp = try await makeExpiredTTP()
        stub.configStatuses = [401]

        let result = try await ttp.charge(type: .sale, paymentDetails: PayabliTTPPaymentDetails(amount: 1, currency: "USD"))

        XCTAssertEqual(result.paymentTransId, RenewalStub.paymentTransId)
        XCTAssertEqual(stub.configBearers.count, 3, "initialize, the refused repair, the renewed repair")
        XCTAssertEqual(tokens.count, 2)
    }

    // MARK: - The activation

    func testARefusedTokenOnActivationIsRenewedAndTheCodeIsSentOnceMore() async throws {
        let (ttp, attestation) = try await makePendingTTP()
        attestation.activationFailuresFirst = [PinnedTokenRefusal()]

        try await ttp.activateDevice(activationCode: "123456")

        XCTAssertEqual(ttp.sessionState, .idle)
        XCTAssertEqual(attestation.activateCalls, 2)
    }

    func testASecondRefusalOnActivationReportsAnExpiredTokenAndLeavesTheSessionWaiting() async throws {
        let (ttp, attestation) = try await makePendingTTP()
        attestation.activationFailuresFirst = [PinnedTokenRefusal(), PinnedTokenRefusal()]

        let failure = await failure { try await ttp.activateDevice(activationCode: "123456") }

        XCTAssertEqual((failure as? any PayabliError)?.code, 1002, "got \(failure)")
        XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "dev_pending"))
        XCTAssertEqual(attestation.activateCalls, 2)
    }

    // MARK: - Every way in

    /// Fails to compile when a kind is added, and fails when a kind's sequence does not renew.
    func testEveryKindOfSessionSetupRenewsARefusedToken() async throws {
        for kind in SessionSetupKind.allCases {
            stub = RenewalStub()
            tokens = TokenCalls()
            StubURLProtocol.handler = stub.handle
            let renewed: Bool
            switch kind {
            case .initialize:
                let (ttp, _, attestation, _) = try makeTTP()
                attestation.isAlreadyAttested = true
                stub.configStatuses = [401]
                try await ttp.initialize()
                renewed = ttp.sessionState == .ready
            case .reinitialize:
                let ttp = try await makeExpiredTTP()
                stub.configStatuses = [401]
                try await ttp.reinitialize()
                renewed = ttp.sessionState == .ready
            case .activate:
                let (ttp, attestation) = try await makePendingTTP()
                attestation.activationFailuresFirst = [PinnedTokenRefusal()]
                try await ttp.activateDevice(activationCode: "123456")
                renewed = ttp.sessionState == .idle
            }
            XCTAssertTrue(renewed, "\(kind) did not renew a refused token")
        }
    }

    // MARK: - What a renewed run reports

    func testARenewedInitializeReportsOneStartAndOneOutcomeAndEachAttestationAttempt() async throws {
        let (ttp, _, attestation, telemetry) = try makeTTP()
        attestation.attestFailuresFirst = [PinnedTokenRefusal()]

        try await ttp.initialize()
        await ttp.reports.sent()
        await ttp.session.telemetry.flush()

        let events = await telemetry.batches.flatMap { $0 }
        let names = events.map(\.event)
        XCTAssertEqual(names.filter { $0 == "ttp.initialize.started" }.count, 1, "\(names)")
        XCTAssertEqual(names.filter { $0 == "ttp.initialize.succeeded" }.count, 1, "\(names)")
        XCTAssertEqual(names.filter { $0 == "ttp.initialize.failed" }.count, 0, "\(names)")
        XCTAssertEqual(
            names.filter { $0.hasPrefix("ttp.attestation.") },
            ["ttp.attestation.started", "ttp.attestation.failed", "ttp.attestation.started", "ttp.attestation.succeeded"]
        )
        let failed = try XCTUnwrap(events.first { $0.event == "ttp.attestation.failed" })
        XCTAssertEqual(failed.properties["error_number"], "1002")
        XCTAssertEqual(failed.properties["outcome"], "failed")
    }

    // MARK: - Fixtures

    private func makeTTP(
        renewalFails: Bool = false
    ) throws -> (PayabliTTP, MockTapToPayProvider, MockDeviceAttestationService, InMemoryTelemetryTransport) {
        let tokens = tokens
        let config = try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: {
            let call = tokens.next()
            if call > 1, renewalFails {
                throw URLError(.notConnectedToInternet)
            }
            return call == 1 ? "seed" : "renewed-\(call)"
        })
        let provider = MockTapToPayProvider()
        provider.readingResult = .success(CardReadResult(provider: "mock", encryptedPayload: Data(), outcome: .approved))
        let attestation = MockDeviceAttestationService()
        let telemetry = InMemoryTelemetryTransport()
        let ttp = PayabliTTP(
            config: config,
            provider: provider,
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession(),
            telemetry: telemetry
        )
        return (ttp, provider, attestation, telemetry)
    }

    /// Ready, then expired, the way a dead reader session leaves it.
    private func makeExpiredTTP() async throws -> PayabliTTP {
        let (ttp, _, attestation, _) = try makeTTP()
        attestation.isAlreadyAttested = true
        try await ttp.initialize()
        XCTAssertTrue(ttp.sessionManager.transition(to: .sessionExpired), "the fixture itself is broken")
        ttp.syncPublished()
        return ttp
    }

    /// Waiting for an activation code.
    private func makePendingTTP() async throws -> (PayabliTTP, MockDeviceAttestationService) {
        let (ttp, _, attestation, _) = try makeTTP()
        attestation.pendingRegistration = "dev_pending"
        _ = await failure { try await ttp.initialize() }
        XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "dev_pending"), "the fixture itself is broken")
        return (ttp, attestation)
    }

    /// What `block` threw. A success fails the test here, so the assertions after it are never quietly skipped.
    private func failure(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ block: () async throws -> Void
    ) async -> any Error {
        do {
            try await block()
            XCTFail("expected a failure, got a success", file: file, line: line)
            return CancellationError()
        } catch {
            return error
        }
    }
}

/// Counts the provider's calls from any isolation.
private final class TokenCalls: @unchecked Sendable {
    private let lock = NSLock()
    private var calls = 0

    var count: Int {
        lock.withLock { calls }
    }

    func next() -> Int {
        lock.withLock {
            calls += 1
            return calls
        }
    }
}

/// Answers `/config` from a script of statuses, then 200, and every payment route with one payment.
private final class RenewalStub: @unchecked Sendable {
    static let paymentTransId = "tx_renewal"

    private let lock = NSLock()
    private var statuses: [Int] = []
    private var refusalText: String?
    private var bearers: [String] = []
    private var configHook: (@Sendable (Int) -> Void)?

    /// Runs on each `/config` call with its one-based number, before the answer is chosen.
    var onConfig: (@Sendable (Int) -> Void)? {
        get { lock.withLock { configHook } }
        set { lock.withLock { configHook = newValue } }
    }

    /// Consumed one per `/config` call; once empty, `/config` answers 200.
    var configStatuses: [Int] {
        get { lock.withLock { statuses } }
        set { lock.withLock { statuses = newValue } }
    }

    /// The `resultText` a refused `/config` carries, or none for a bare status.
    var configRefusalText: String? {
        get { lock.withLock { refusalText } }
        set { lock.withLock { refusalText = newValue } }
    }

    /// The bearer each `/config` call carried, in order.
    var configBearers: [String] {
        lock.withLock { bearers }
    }

    func handle(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let path = request.url?.path ?? ""
        if path.contains("/MoneyIn/") {
            let body = ["code": "A01", "data": ["paymentTransId": Self.paymentTransId]] as [String: Any]
            return try Self.reply(request, 200, JSONSerialization.data(withJSONObject: body))
        }
        let bearer = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "")
        let (call, hook): (Int, (@Sendable (Int) -> Void)?) = lock.withLock {
            bearers.append(bearer ?? "")
            return (bearers.count, configHook)
        }
        hook?(call)
        let (status, text): (Int, String?) = lock.withLock {
            (statuses.isEmpty ? 200 : statuses.removeFirst(), refusalText)
        }
        if status != 200 {
            let body = text.map {
                #"{"isSuccess":false,"responseText":"Declined","responseData":{"resultCode":\#(status),"resultText":"\#($0)"}}"#
            } ?? ""
            return Self.reply(request, status, Data(body.utf8))
        }
        let body: [String: Any] = [
            "responseCode": 1,
            "isSuccess": true,
            "responseData": ["credentials": ["secretKey": "s", "apiKey": "a", "merchantId": "m", "terminalId": "t"]]
        ]
        return try Self.reply(request, 200, JSONSerialization.data(withJSONObject: body))
    }

    private static func reply(_ request: URLRequest, _ status: Int, _ data: Data) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(
            url: request.url!,
            statusCode: status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!, data)
    }
}

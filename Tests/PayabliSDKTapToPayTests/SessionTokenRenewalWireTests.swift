@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// The renewal end to end over the wire: the facade's own transport records the token a device route
/// refused, the session renews it, and the sequence's second run carries the new token.
@available(iOS 16.7, *)
@MainActor
final class SessionTokenRenewalWireTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testAColdStartWhoseAttestRefusedItsTokenRenewsItAndAttestsUnderTheNewOne() async throws {
        let wire = Wire(refusing: "attest")
        StubURLProtocol.handler = wire.handle
        let (ttp, tokens) = try makeTTP()

        try await ttp.initialize()

        XCTAssertEqual(ttp.sessionState, .ready)
        XCTAssertEqual(wire.bearers(for: "attest"), ["seed", "renewed-2"], "the second attest carried a renewed token")
        XCTAssertEqual(tokens.count, 2, "one renewal")
    }

    func testAnActivationWhoseTokenWasRefusedRenewsItAndSendsTheCodeUnderTheNewOne() async throws {
        let wire = Wire(refusing: "activate", registersPending: true)
        StubURLProtocol.handler = wire.handle
        let (ttp, tokens) = try makeTTP()
        do {
            try await ttp.initialize()
            XCTFail("a pending registration reported ready")
        } catch {}
        guard case .pendingActivation = ttp.sessionState else {
            return XCTFail("the fixture itself is broken: \(ttp.sessionState)")
        }

        try await ttp.activateDevice(activationCode: "123456")

        XCTAssertEqual(ttp.sessionState, .idle)
        XCTAssertEqual(wire.bearers(for: "activate"), ["seed", "renewed-2"], "the second activate carried a renewed token")
        XCTAssertEqual(tokens.count, 2, "one renewal")
    }

    // MARK: - The routes before a binding exists

    func testAColdStartWhoseChallengeRefusedItsTokenRenewsItAndAttests() async throws {
        let wire = Wire(refusing: "challenge")
        StubURLProtocol.handler = wire.handle
        let (ttp, tokens) = try makeTTP()

        try await ttp.initialize()

        XCTAssertEqual(ttp.sessionState, .ready)
        XCTAssertEqual(wire.bearers(for: "challenge"), ["seed", "renewed-2"])
        XCTAssertEqual(tokens.count, 2, "one renewal")
    }

    func testAColdStartWhoseRegisterRefusedItsTokenRenewsItAndRunsTheSequenceAgain() async throws {
        let wire = Wire(refusing: "register")
        StubURLProtocol.handler = wire.handle
        let (ttp, tokens) = try makeTTP()

        try await ttp.initialize()

        XCTAssertEqual(ttp.sessionState, .ready)
        XCTAssertEqual(wire.bearers(for: "challenge"), ["seed", "renewed-2"], "the sequence ran again from its first request")
        XCTAssertEqual(wire.bearers(for: "register"), ["seed", "renewed-2"])
        XCTAssertEqual(tokens.count, 2, "one renewal")
    }

    func testAChallengeRefusedAgainAfterTheRenewalThrows1002AndLeavesTheSessionUsable() async throws {
        try await assertRefusedAgainLeavesTheSessionUsable(at: "challenge")
    }

    func testARegisterRefusedAgainAfterTheRenewalThrows1002AndLeavesTheSessionUsable() async throws {
        try await assertRefusedAgainLeavesTheSessionUsable(at: "register")
    }

    /// The held refusal can be the event that fills a batch, which sends it at once. It is held until the renewal has
    /// run, so that send carries the renewed token and not the one being replaced.
    func testARenewableRefusalThatFillsTheBatchLeavesUnderTheRenewedToken() async throws {
        let wire = Wire(refusing: "attest")
        StubURLProtocol.handler = wire.handle
        let renewal = RenewalGate()
        let (ttp, _) = try makeTTP(renewal: renewal)
        // Three short of a batch with the session's own start: the setup's start, the attempt and its refusal make twenty.
        for _ in 0 ..< 16 {
            await ttp.session.telemetry.emit(TelemetryEventName.ttpInitializeStarted)
        }

        let setup = Task { try await ttp.initialize() }
        await renewal.waitUntilAsked()
        await ttp.reports.sent()
        XCTAssertEqual(wire.bearers(for: "telemetry"), [], "a batch was sent while the token was being replaced")
        renewal.release()
        try await setup.value
        await ttp.reports.sent()

        XCTAssertEqual(wire.bearers(for: "telemetry").first, "renewed-2")
    }

    // MARK: - Fixtures

    /// A cold `initialize` whose `route` refuses the seed and the renewed token throws 1002, lands `serviceUnavailable`,
    /// and leaves the session's credential usable: the next request on the session is sent.
    private func assertRefusedAgainLeavesTheSessionUsable(
        at route: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let wire = Wire(refusing: route, times: 2)
        StubURLProtocol.handler = wire.handle
        let (ttp, tokens) = try makeTTP()

        do {
            try await ttp.initialize()
            XCTFail("a twice-refused \(route) reported ready", file: file, line: line)
        } catch {
            XCTAssertEqual((error as? any PayabliError)?.type, .tokenExpired, "got \(error)", file: file, line: line)
        }

        XCTAssertEqual(ttp.sessionState, .failed(reason: .serviceUnavailable), file: file, line: line)
        XCTAssertEqual(wire.bearers(for: route), ["seed", "renewed-2"], file: file, line: line)
        XCTAssertEqual(tokens.count, 2, "one renewal", file: file, line: line)
        _ = try await ttp.session.transport.perform(PayabliRequest(method: .get, path: "/api/v2/ping"))
        XCTAssertEqual(wire.bearers(for: "/api/v2/ping"), ["renewed-2"], "the session refused a later call", file: file, line: line)
        // The failure's report is sent after the throw, and would otherwise reach the next test's stub.
        await ttp.reports.sent()
    }

    /// A facade whose attestation service runs on the facade's own session, so a refusal is recorded where the
    /// renewal reads it.
    private func makeTTP(renewal: RenewalGate? = nil) throws -> (PayabliTTP, Tokens) {
        let tokens = Tokens()
        let config = try PayabliConfig(entryPoint: "myEntry", environment: .sandbox, tokenProvider: {
            let call = tokens.next()
            if call > 1 {
                await renewal?.ask()
            }
            return call == 1 ? "seed" : "renewed-\(call)"
        })
        let session = PayabliSession(config: config, urlSession: StubURLProtocol.makeSession())
        let attestation = AppAttestService(
            transport: session.transport,
            attestor: MockAppAttestor(),
            storage: InMemorySecureStorage(),
            hardwareIdProvider: { "fixed-hw-id" },
            appIdProvider: { "TEAM.bundle.id" },
            modelProvider: { "iPhone15,2" },
            osVersionProvider: { "17.0" }
        )
        let ttp = PayabliTTP(
            session: session,
            provider: MockTapToPayProvider(),
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            // The session was never installed, so it reads as live only because the test says so.
            isLive: { true }
        )
        return (ttp, tokens)
    }
}

/// Counts the provider's calls from any isolation.
private final class Tokens: @unchecked Sendable {
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

/// Holds the provider's renewal open until the test releases it, and says when it has been asked.
private final class RenewalGate: @unchecked Sendable {
    private let lock = NSLock()
    private var asked = false
    private var released = false
    private var waiting: CheckedContinuation<Void, Never>?

    func ask() async {
        await withCheckedContinuation { continuation in
            let resumeNow: Bool = lock.withLock {
                asked = true
                if released {
                    return true
                }
                waiting = continuation
                return false
            }
            if resumeNow {
                continuation.resume()
            }
        }
    }

    func release() {
        let continuation: CheckedContinuation<Void, Never>? = lock.withLock {
            released = true
            defer { waiting = nil }
            return waiting
        }
        continuation?.resume()
    }

    /// Polled under a ceiling, so a renewal that never starts fails the test rather than hanging the suite.
    func waitUntilAsked(file: StaticString = #filePath, line: UInt = #line) async {
        for _ in 0 ..< 300 {
            if lock.withLock({ asked }) {
                return
            }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
        release()
        XCTFail("the renewal was never asked for", file: file, line: line)
    }
}

/// Every device route answering as the service does, with one route refusing its first `times` requests with a bare
/// 401. A request outside the device routes is recorded under its path and answered with success.
private final class Wire: @unchecked Sendable {
    private let lock = NSLock()
    private let refused: String
    private let registersPending: Bool
    private var refusalsLeft: Int
    private var seen: [String: [String]] = [:]

    init(refusing route: String, times: Int = 1, registersPending: Bool = false) {
        refused = route
        refusalsLeft = times
        self.registersPending = registersPending
    }

    /// The bearer each request to `route` carried, in order.
    func bearers(for route: String) -> [String] {
        lock.withLock { seen[route] ?? [] }
    }

    func handle(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let path = request.url?.path ?? ""
        let devicePrefix = "/api/v2/device/taptopay/"
        let route = path.hasSuffix(TelemetryEndpointTransport.defaultPath) ? "telemetry"
            : !path.hasPrefix(devicePrefix) ? path
            : path.replacingOccurrences(of: devicePrefix, with: "").components(separatedBy: "/")[0]
        let bearer = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "")
        let refuses: Bool = lock.withLock {
            seen[route, default: []].append(bearer ?? "")
            guard route == refused, refusalsLeft > 0 else { return false }
            refusalsLeft -= 1
            return true
        }
        if refuses {
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)!, Data())
        }
        switch route {
        case "challenge":
            return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
        case "register":
            return AttestFixture.ok(request, registersPending ? ["deviceId": "dev_1", "status": "pending"] : ["deviceId": "dev_1"])
        case "config":
            return AttestFixture.ok(request, ["credentials": ["secretKey": "s", "apiKey": "a", "merchantId": "m", "terminalId": "t"]])
        default:
            return AttestFixture.ok(request, ["ok": true])
        }
    }
}

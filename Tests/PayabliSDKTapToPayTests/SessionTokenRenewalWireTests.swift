@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// The renewal end to end over the wire: the facade's own transport records the token `/attest` or `/activate`
/// refused, the session renews it, and the sequence's second run carries the new token.
@available(iOS 16.7, *)
@MainActor
final class SessionTokenRenewalWireTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testAColdStartWhoseAttestRefusedItsTokenRenewsItAndAttestsUnderTheNewOne() async throws {
        let wire = Wire(refusingOnce: "attest")
        StubURLProtocol.handler = wire.handle
        let (ttp, tokens) = try makeTTP()

        try await ttp.initialize()

        XCTAssertEqual(ttp.sessionState, .ready)
        XCTAssertEqual(wire.bearers(for: "attest"), ["seed", "renewed-2"], "the second attest carried a renewed token")
        XCTAssertEqual(tokens.count, 2, "one renewal")
    }

    func testAnActivationWhoseTokenWasRefusedRenewsItAndSendsTheCodeUnderTheNewOne() async throws {
        let wire = Wire(refusingOnce: "activate", registersPending: true)
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

    // MARK: - Fixtures

    /// A facade whose attestation service runs on the facade's own session, so a refusal is recorded where the
    /// renewal reads it.
    private func makeTTP() throws -> (PayabliTTP, Tokens) {
        let tokens = Tokens()
        let config = try PayabliConfig(entryPoint: "myEntry", environment: .sandbox, tokenProvider: {
            let call = tokens.next()
            return call == 1 ? "seed" : "renewed-\(call)"
        }, telemetryEnabled: false)
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
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0)
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

/// Every device route answering as the service does, with one route refusing its first request with a bare 401.
private final class Wire: @unchecked Sendable {
    private let lock = NSLock()
    private let refused: String
    private let registersPending: Bool
    private var refusedOnce = false
    private var seen: [String: [String]] = [:]

    init(refusingOnce route: String, registersPending: Bool = false) {
        refused = route
        self.registersPending = registersPending
    }

    /// The bearer each request to `route` carried, in order.
    func bearers(for route: String) -> [String] {
        lock.withLock { seen[route] ?? [] }
    }

    func handle(_ request: URLRequest) throws -> (HTTPURLResponse, Data) {
        let path = request.url?.path ?? ""
        let route = path.replacingOccurrences(of: "/api/v2/device/taptopay/", with: "").components(separatedBy: "/")[0]
        let bearer = request.value(forHTTPHeaderField: "Authorization")?.replacingOccurrences(of: "Bearer ", with: "")
        let refuses: Bool = lock.withLock {
            seen[route, default: []].append(bearer ?? "")
            guard route == refused, !refusedOnce else { return false }
            refusedOnce = true
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

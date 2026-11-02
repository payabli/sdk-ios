@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// A refusal naming the entry point reports `ENTRY_POINT_REFUSED` and lands on a rejected configuration, from the
/// configuration route and from setting the device up alike. A configuration 403 whose words name nothing classified
/// still asks for an activation code.
@available(iOS 16.7, *)
@MainActor
final class EntryPointRefusalTests: XCTestCase {
    private static let entryPointUnusable = "Entry point is not available for this request."

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - /config, a phone holding a registration

    func testAConfigurationRefusedForTheEntryPointIs3009AndKeepsTheRegistration() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.cachedDeviceId = "dev_1"
        StubURLProtocol.handler = { request in Self.refusal(request, status: 403, reason: Self.entryPointUnusable) }

        let type = await initializeFailure(ttp)

        XCTAssertEqual(type, .entryPointRefused)
        XCTAssertEqual(ttp.sessionState, .failed(reason: .configurationRejected))
        XCTAssertEqual(attestation.cachedDeviceId, "dev_1", "the registration is kept")
    }

    func testAConfigurationRefusalForTheEntryPointInsideASuccessfulResponseIs3009() async throws {
        let (ttp, attestation) = try makeTTP()
        attestation.cachedDeviceId = "dev_1"
        StubURLProtocol.handler = { request in
            Self.refusal(request, status: 200, resultCode: 403, reason: Self.entryPointUnusable)
        }

        let type = await initializeFailure(ttp)

        XCTAssertEqual(type, .entryPointRefused)
        XCTAssertEqual(ttp.sessionState, .failed(reason: .configurationRejected))
        XCTAssertEqual(attestation.cachedDeviceId, "dev_1", "the registration is kept")
    }

    /// Only the service's exact words name the entry point. Anything near them, and a 403 with no body at all,
    /// is the device still owing its code.
    func testAnyOther403OnTheConfigurationStillAsksForTheActivationCode() async throws {
        let bodies: [String?] = [
            "Device is not in a state that allows this operation.",
            "Entry point is not available for this request. ",
            "entry point is not available for this request.",
            "Entry point is not available",
            nil
        ]
        for reason in bodies {
            let (ttp, attestation) = try makeTTP()
            attestation.cachedDeviceId = "dev_1"
            StubURLProtocol.handler = { request in
                guard let reason else { return Self.bodiless(request, status: 403) }
                return Self.refusal(request, status: 403, reason: reason)
            }

            _ = await initializeFailure(ttp)

            XCTAssertEqual(ttp.sessionState, .pendingActivation(activationId: "dev_1"), "\(reason ?? "no body")")
        }
    }

    // MARK: - Over the wire, through the facade

    /// The device has never been set up, and `/attest` refuses the entry point.
    func testASetupRefusedForTheEntryPointReachesTheSessionAsARejectedConfiguration() async throws {
        StubURLProtocol.handler = { request in
            switch Self.route(of: request) {
            case "challenge":
                return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
            case "register":
                return AttestFixture.ok(request, ["deviceId": "dev_1"])
            case "attest":
                return Self.refusal(request, status: 403, reason: Self.entryPointUnusable)
            default:
                return AttestFixture.ok(request, ["ok": true])
            }
        }
        let (ttp, attestation) = try makeWiredTTP()

        let type = await initializeFailure(ttp)

        XCTAssertEqual(type, .entryPointRefused)
        XCTAssertEqual(ttp.sessionState, .failed(reason: .configurationRejected))
        XCTAssertNil(try attestation.binding(for: "myEntry"), "nothing was bound")
    }

    /// The device is set up, and `/config` refuses the entry point.
    func testAConfigurationRefusedForTheEntryPointReachesTheSessionAndKeepsTheBinding() async throws {
        let storage = InMemorySecureStorage()
        try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev_1", keyId: "key_1", in: storage)
        StubURLProtocol.handler = { request in
            guard Self.route(of: request) == "config" else { return AttestFixture.ok(request, ["ok": true]) }
            return Self.refusal(request, status: 403, reason: Self.entryPointUnusable)
        }
        let (ttp, attestation) = try makeWiredTTP(storage: storage)

        let type = await initializeFailure(ttp)

        XCTAssertEqual(type, .entryPointRefused)
        XCTAssertEqual(ttp.sessionState, .failed(reason: .configurationRejected))
        XCTAssertEqual(try attestation.binding(for: "myEntry")?.deviceId, "dev_1", "the binding is kept")
    }

    // MARK: - Fixtures

    /// Runs `initialize` expecting it to fail, and answers the catalog type the host was given.
    private func initializeFailure(_ ttp: PayabliTTP) async -> PayabliErrorType? {
        do {
            try await ttp.initialize()
            XCTFail("initialize reported success")
            return nil
        } catch {
            return (error as? TapToPayError)?.type
        }
    }

    private func makeTTP() throws -> (PayabliTTP, MockDeviceAttestationService) {
        let attestation = MockDeviceAttestationService()
        let config = try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" })
        let ttp = PayabliTTP(
            config: config,
            provider: MockTapToPayProvider(),
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
        return (ttp, attestation)
    }

    /// A facade whose attestation service sends its requests on the facade's own session, so a refusal travels
    /// the whole path a host's does.
    private func makeWiredTTP(
        storage: SecureStorage = InMemorySecureStorage()
    ) throws -> (PayabliTTP, AppAttestService) {
        let config = try PayabliConfig(entryPoint: "myEntry", environment: .sandbox, tokenProvider: { "seed" })
        let session = PayabliSession(config: config, urlSession: StubURLProtocol.makeSession())
        let attestation = AppAttestService(
            transport: session.transport,
            attestor: MockAppAttestor(),
            storage: storage,
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
        return (ttp, attestation)
    }

    private nonisolated static func route(of request: URLRequest) -> String {
        let path = request.url?.path ?? ""
        return path.replacingOccurrences(of: "/api/v2/device/taptopay/", with: "").components(separatedBy: "/")[0]
    }

    /// A refusal the way the service sends one, its result code as the HTTP status unless told otherwise.
    private nonisolated static func refusal(
        _ request: URLRequest,
        status: Int,
        resultCode: Int? = nil,
        reason: String
    ) -> (HTTPURLResponse, Data) {
        let body: [String: Any] = [
            "isSuccess": false,
            "responseText": "Declined",
            "responseData": ["resultCode": resultCode ?? status, "resultText": reason]
        ]
        return (
            HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!,
            try! JSONSerialization.data(withJSONObject: body)
        )
    }

    private nonisolated static func bodiless(_ request: URLRequest, status: Int) -> (HTTPURLResponse, Data) {
        (HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, Data())
    }
}

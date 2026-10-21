@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// Telemetry goes out through the SDK's own request path, so a batch carries the credential and needs
/// no network layer of its own.
final class TelemetryEndpointTransportTests: XCTestCase {
    func testABatchIsPostedThroughTheChainAndCarriesTheCredential() async {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }

        let service = PayabliService(
            environment: .sandbox,
            readToken: { "telemetry-token" },
            client: .none,
            session: StubURLProtocol.makeSession()
        )
        let subject = TelemetryEndpointTransport(transport: service)

        await subject.send([event()])

        XCTAssertEqual(stub.count, 1)
        XCTAssertEqual(stub.sentTokens, ["telemetry-token"])
        XCTAssertEqual(stub.requests.first?.httpMethod, "POST")
        XCTAssertEqual(
            stub.requests.first?.url?.path,
            TelemetryEndpointTransport.defaultPath
        )
        XCTAssertEqual(
            stub.requests.first?.value(forHTTPHeaderField: "Content-Type"),
            "application/json"
        )
    }

    func testAnEmptyBatchSendsNothing() async {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }

        let service = PayabliService(
            environment: .sandbox,
            readToken: { "telemetry-token" },
            client: .none,
            session: StubURLProtocol.makeSession()
        )

        await TelemetryEndpointTransport(transport: service).send([])

        XCTAssertEqual(stub.count, 0)
    }

    /// Best-effort: a refused batch is not a payment's problem, so nothing propagates.
    func testAFailureIsSwallowed() async {
        let stub = RecordingStub(status: 500)
        stub.install()
        defer { stub.uninstall() }

        let service = PayabliService(
            environment: .sandbox,
            readToken: { "telemetry-token" },
            client: .none,
            session: StubURLProtocol.makeSession()
        )

        await TelemetryEndpointTransport(transport: service).send([event()])

        XCTAssertEqual(stub.count, 1, "it was attempted and not retried")
    }

    /// A token the read refuses stops the batch, and still does not propagate.
    func testARefusedCredentialSwallowsRatherThanSendingUnauthenticated() async {
        struct NoToken: Error {}

        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }

        let service = PayabliService(
            environment: .sandbox,
            readToken: { throw NoToken() },
            client: .none,
            session: StubURLProtocol.makeSession()
        )

        await TelemetryEndpointTransport(transport: service).send([event()])

        XCTAssertEqual(stub.count, 0)
    }

    func testAFinishedSessionSendsNoBatch() async throws {
        let stub = RecordingStub(status: 401)
        stub.install()
        defer { stub.uninstall() }
        let calls = Counter()
        let session = try makeSession(tokenProvider: { await "refused-token-\(calls.increment())" })
        _ = try? await session.transport.perform(PayabliRequest(method: .get, path: "/api/v2/ping"))
        XCTAssertNotNil(session.auth.terminalFailure, "a refused replay finished the session")
        let sentBefore = stub.count

        await session.telemetry.emit("sdk_initialized")
        await session.telemetry.flush()

        XCTAssertEqual(stub.count, sentBefore, "the batch never left")
    }

    func testARefusedBatchNeitherRefreshesNorReplaysNorFinishesTheSession() async throws {
        let stub = RecordingStub(status: 401)
        stub.install()
        defer { stub.uninstall() }
        let provider = Counter()
        let session = try makeSession(tokenProvider: {
            _ = await provider.increment()
            return "telemetry-token"
        })

        await session.telemetry.emit("sdk_initialized")
        await session.telemetry.flush()

        XCTAssertEqual(stub.count, 1, "no replay")
        let calls = await provider.count
        XCTAssertEqual(calls, 1, "the first token only, no refresh")
        XCTAssertNil(session.auth.terminalFailure)
    }

    /// A session built the way a host's is, so its batches take the production route.
    private func makeSession(tokenProvider: @escaping PayabliTokenRefresh) throws -> PayabliSession {
        let config = try PayabliConfig(entryPoint: "entry", environment: .sandbox, tokenProvider: tokenProvider)
        return PayabliSession(config: config, urlSession: StubURLProtocol.makeSession())
    }

    private func event() -> TelemetryEvent {
        TelemetryEvent(
            sdkVersion: "0.1.0",
            sessionId: "session-1",
            deviceIdHash: nil,
            entry: "entry",
            environment: "sandbox",
            event: "sdk_initialized",
            properties: [:]
        )
    }
}

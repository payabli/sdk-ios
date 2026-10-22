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

        await subject.send([event()], droppedSinceLastSend: 0)

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

    /// A batch carries no pin and declares a 401 a refusal of its caller, so a refusal of the batch
    /// is not recorded for the device setup to renew.
    func testABatchCarriesNoPinAndDeclaresA401ARefusalOfItsCaller() async throws {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }
        let recording = RecordingDecoration()
        let transport = makeStackWithChain([recording], auth: try makeTestAuth())

        await TelemetryEndpointTransport(transport: transport).send([event()], droppedSinceLastSend: 0)

        let request = try XCTUnwrap(recording.observed.first)
        XCTAssertFalse(request.pinsCredential, "a refusal is not recorded for the device setup to renew")
        XCTAssertTrue(request.isCallerRefusal(answered(401)), "a 401 refuses the caller")
        XCTAssertFalse(request.isCallerRefusal(answered(200)), "an accepted batch does not")
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

        await TelemetryEndpointTransport(transport: service).send([], droppedSinceLastSend: 0)

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

        await TelemetryEndpointTransport(transport: service).send([event()], droppedSinceLastSend: 0)

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

        await TelemetryEndpointTransport(transport: service).send([event()], droppedSinceLastSend: 0)

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

    /// A refused batch leaves nothing for the setup to renew, so a setup that follows asks the
    /// provider for nothing.
    func testARefusedBatchLeavesNothingForTheSetupToRenewAndAsksTheProviderForNothing() async throws {
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
        let renewed = try await session.auth.renewPinnedRefusal()
        XCTAssertFalse(renewed, "a refused batch leaves nothing for the setup to renew")
        let calls = await provider.count
        XCTAssertEqual(calls, 1, "the first token only; the setup asked the provider for nothing")
    }

    func testA401IsKeptForTheNextFlush() async throws {
        let outcome = try await sendAgainst(status: 401)
        XCTAssertEqual(outcome, .kept)
    }

    func testA429IsKeptForTheNextFlush() async throws {
        let outcome = try await sendAgainst(status: 429)
        XCTAssertEqual(outcome, .kept)
    }

    func testA5xxIsKeptForTheNextFlush() async throws {
        let outcome = try await sendAgainst(status: 500)
        XCTAssertEqual(outcome, .kept)
    }

    func testA413IsDiscarded() async throws {
        let outcome = try await sendAgainst(status: 413)
        XCTAssertEqual(outcome, .discarded)
    }

    func testAnAcceptedBatchIsDelivered() async throws {
        let outcome = try await sendAgainst(status: 202)
        XCTAssertEqual(outcome, .delivered)
    }

    /// A send that never reaches an answer is kept too: the next flush tries the batch again.
    func testATransportFailureIsKeptForTheNextFlush() async {
        struct NoAnswer: Error {}

        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }
        let service = PayabliService(
            environment: .sandbox,
            readToken: { throw NoAnswer() },
            client: .none,
            session: StubURLProtocol.makeSession()
        )

        let outcome = await TelemetryEndpointTransport(transport: service).send([event()], droppedSinceLastSend: 0)

        XCTAssertEqual(outcome, .kept)
    }

    /// A session built the way a host's is, so its batches take the production route.
    private func makeSession(tokenProvider: @escaping PayabliTokenRefresh) throws -> PayabliSession {
        let config = try PayabliConfig(entryPoint: "entry", environment: .sandbox, tokenProvider: tokenProvider)
        return PayabliSession(config: config, urlSession: StubURLProtocol.makeSession())
    }

    /// Sends one batch against a stub answering one status, and returns what the send said about it.
    private func sendAgainst(status: Int) async throws -> TelemetrySendOutcome {
        let stub = RecordingStub(status: status)
        stub.install()
        defer { stub.uninstall() }
        let service = PayabliService(
            environment: .sandbox,
            readToken: { "telemetry-token" },
            client: .none,
            session: StubURLProtocol.makeSession()
        )
        return await TelemetryEndpointTransport(transport: service).send([event()], droppedSinceLastSend: 0)
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

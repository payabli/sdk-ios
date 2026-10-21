@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// The session owns one telemetry client, reporting under its own entry point and environment, and a
/// refusal on the telemetry route never touches the credential a payment is using.
final class PayabliSessionTelemetryTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PayabliSession.resetForTesting()
    }

    override func tearDown() {
        PayabliSession.resetForTesting()
        super.tearDown()
    }

    func testTheSessionReportsUnderItsEntryPointAndEnvironment() async throws {
        let transport = InMemoryTelemetryTransport()
        let session = PayabliSession(
            config: try makeConfig(),
            urlSession: StubURLProtocol.makeSession(),
            telemetryTransport: transport
        )

        await session.telemetry.emit(TelemetryEventName.ttpInitializeStarted)
        await session.telemetry.flush()

        let events = await transport.batches.flatMap { $0 }
        let sent = try XCTUnwrap(events.first { $0.event == "ttp.initialize.started" })
        XCTAssertEqual(sent.entry, "demo")
        XCTAssertEqual(sent.environment, "sandbox")
    }

    func testAnInstalledSessionReportsItsStartFirstWithNoHostCode() async throws {
        let transport = InMemoryTelemetryTransport()
        let session = try PayabliSession.install(config: makeConfig(), telemetryTransport: transport)

        await session.telemetry.emit(TelemetryEventName.ttpInitializeStarted)
        await session.telemetry.flush()

        let events = await transport.batches.flatMap { $0 }
        XCTAssertEqual(events.map(\.event), ["sdk.initialized", "ttp.initialize.started"])
        XCTAssertEqual(events.first?.properties, ["state": "ready"])
        XCTAssertEqual(events.first?.sessionId, session.telemetry.sessionId)
    }

    func testARefusedRepeatCallReportsAStartAndAFailureOnTheLiveSession() async throws {
        let transport = InMemoryTelemetryTransport()
        let live = try PayabliSession.install(config: makeConfig(), telemetryTransport: transport)

        do {
            try await PayabliSession.initialize(config: makeConfig(entryPoint: "other"))
            XCTFail("a different configuration was accepted")
        } catch {}
        await live.telemetry.settled()

        let events = await transport.batches.flatMap { $0 }
        guard events.map(\.event) == ["sdk.initialized", "sdk.initialize.started", "sdk.initialize.failed"] else {
            return XCTFail("sent without a flush, because a failure leaves at once: \(events.map(\.event))")
        }
        XCTAssertTrue(events.allSatisfy { $0.sessionId == live.telemetry.sessionId && $0.entry == "demo" })
        XCTAssertEqual(events[1].properties, ["state": "ready"])
        let failed = events[2].properties
        XCTAssertEqual(Set(failed.keys), ["outcome", "code", "error_number", "reason", "duration_ms"])
        XCTAssertEqual(failed["outcome"], "refused")
        XCTAssertEqual(failed["code"], "INVALID_CONFIGURATION")
        XCTAssertEqual(failed["error_number"], String(PayabliErrorType.invalidConfiguration.number))
        XCTAssertEqual(failed["reason"], "a session is already initialized with a different configuration")
        XCTAssertNotNil(Int(failed["duration_ms"] ?? ""))
    }

    func testARepeatCallThatChangesNothingReportsNothing() async throws {
        let transport = InMemoryTelemetryTransport()
        let live = try PayabliSession.install(config: makeConfig(), telemetryTransport: transport)

        let again = try await PayabliSession.initialize(config: makeConfig())
        await live.telemetry.settled()

        XCTAssertTrue(again === live)
        let buffered = await live.telemetry.bufferedCount
        let batches = await transport.batches
        XCTAssertEqual(buffered, 1, "only the start reported at install")
        XCTAssertTrue(batches.isEmpty)
    }

    func testATelemetryRouteThatRefusesEverythingLeavesTheSessionWorking() async throws {
        let transport = InMemoryTelemetryTransport()
        await transport.refuse(true)
        let live = try PayabliSession.install(config: makeConfig(), telemetryTransport: transport)
        await live.telemetry.emit(TelemetryEventName.ttpInitializeFailed, properties: ["outcome": "failed"])
        await live.telemetry.settled()

        let again = try await PayabliSession.initialize(config: makeConfig())

        XCTAssertTrue(again === live)
        let batches = await transport.batches
        XCTAssertEqual(batches.count, 1, "attempted once and not retried")
    }

    func testEveryEventCarriesTheSessionsDeviceIdentifierUnchanged() async throws {
        let transport = InMemoryTelemetryTransport()
        let session = try PayabliSession(
            config: makeConfig(),
            urlSession: StubURLProtocol.makeSession(),
            deviceIdentity: DeviceIdentity { "0f8d2a1c4b6e4a2f9c3d5e7f8a9b0c1d" },
            telemetryTransport: transport
        )

        await session.telemetry.flush()

        let events = await transport.batches.flatMap { $0 }
        XCTAssertEqual(events.first?.deviceIdHash, session.deviceId)
        XCTAssertEqual(events.first?.deviceIdHash, "0f8d2a1c4b6e4a2f9c3d5e7f8a9b0c1d")
    }

    func testADeviceThatCannotBeIdentifiedReportsNoIdentifier() async throws {
        struct Unreadable: Error {}
        let transport = InMemoryTelemetryTransport()
        let session = try PayabliSession(
            config: makeConfig(),
            urlSession: StubURLProtocol.makeSession(),
            deviceIdentity: DeviceIdentity { throw Unreadable() },
            telemetryTransport: transport
        )

        await session.telemetry.flush()

        let events = await transport.batches.flatMap { $0 }
        XCTAssertEqual(events.count, 1)
        XCTAssertNil(events.first?.deviceIdHash)
    }

    /// The default client posts to the telemetry route through the service, beneath the recovery layer.
    func testATelemetry401SpendsNoRefreshAndLeavesTheCredential() async throws {
        let stub = RecordingStub { request in
            request.url?.path == TelemetryEndpointTransport.defaultPath
                ? (401, Data())
                : (200, Data("{}".utf8))
        }
        stub.install()
        defer { stub.uninstall() }
        let calls = Counter()
        let session = PayabliSession(
            config: try makeConfig(tokenProvider: {
                let call = await calls.increment()
                return "token-\(call)"
            }),
            urlSession: StubURLProtocol.makeSession()
        )

        _ = try await session.transport.perform(PayabliRequest(method: .get, path: "/api/v2/before"))
        await session.telemetry.emit(TelemetryEventName.ttpInitializeFailed)
        await session.telemetry.flush()
        _ = try await session.transport.perform(PayabliRequest(method: .get, path: "/api/v2/after"))

        let providerCalls = await calls.count
        XCTAssertEqual(providerCalls, 1, "a telemetry 401 must not mint a new token")
        XCTAssertEqual(stub.requests.map { $0.url?.path }, [
            "/api/v2/before", TelemetryEndpointTransport.defaultPath, TelemetryEndpointTransport.defaultPath, "/api/v2/after"
        ], "the refused batch goes back to the queue and the flush after it sends it again")
        XCTAssertEqual(stub.sentTokens, ["token-1", "token-1", "token-1", "token-1"])
        let body = try XCTUnwrap(stub.requests[1].httpBody)
        let envelope = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(envelope["entry"] as? String, "demo")
    }

    private func makeConfig(
        entryPoint: String = "demo",
        tokenProvider: @escaping PayabliTokenRefresh = { "tok" }
    ) throws -> PayabliConfig {
        try PayabliConfig(
            entryPoint: entryPoint,
            environment: .sandbox,
            tokenProvider: tokenProvider
        )
    }
}

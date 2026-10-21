@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// The session owns one telemetry client, reporting under its own entry point and environment, and a
/// refusal on the telemetry route never touches the credential a payment is using.
final class PayabliSessionTelemetryTests: XCTestCase {
    func testTheSessionReportsUnderItsEntryPointAndEnvironment() async throws {
        let transport = InMemoryTelemetryTransport()
        let session = PayabliSession(
            config: try makeConfig(),
            urlSession: StubURLProtocol.makeSession(),
            telemetryTransport: transport
        )

        await session.telemetry.emit(TelemetryEventName.ttpInitializeStarted)
        await session.telemetry.flush()

        let batches = await transport.batches
        let sent = try XCTUnwrap(batches.first?.first)
        XCTAssertEqual(sent.entry, "demo")
        XCTAssertEqual(sent.environment, "sandbox")
        XCTAssertEqual(sent.event, "ttp.initialize.started")
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
            "/api/v2/before", TelemetryEndpointTransport.defaultPath, "/api/v2/after"
        ], "the refused batch is sent once and not replayed")
        XCTAssertEqual(stub.sentTokens, ["token-1", "token-1", "token-1"])
        let body = try XCTUnwrap(stub.requests[1].httpBody)
        let envelope = try XCTUnwrap(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(envelope["entry"] as? String, "demo")
    }

    private func makeConfig(
        tokenProvider: @escaping PayabliTokenRefresh = { "tok" }
    ) throws -> PayabliConfig {
        try PayabliConfig(
            entryPoint: "demo",
            environment: .sandbox,
            tokenProvider: tokenProvider
        )
    }
}

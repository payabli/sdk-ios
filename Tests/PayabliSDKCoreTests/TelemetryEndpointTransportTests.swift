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
            session: StubURLProtocol.makeSession()
        )

        await TelemetryEndpointTransport(transport: service).send([event()])

        XCTAssertEqual(stub.count, 0)
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

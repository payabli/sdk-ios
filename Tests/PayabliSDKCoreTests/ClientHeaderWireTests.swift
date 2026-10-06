@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// Read off the wire, because what the transport sends is the claim that matters.
final class ClientHeaderWireTests: XCTestCase {
    private let facts = ClientFacts(
        sdkVersion: "0.1.0",
        osVersion: "26.6.2",
        hardware: "iPhone12,3",
        deviceId: { "0123456789abcdef0123456789abcdef" },
        locale: { "en-US" }
    )

    private var expected: String {
        ClientHeader.value(of: facts)
    }

    private func transport(auth: PayabliAuth) -> any PayabliTransport {
        let logger = PayabliLogger(category: .network, sink: RecordingLogSink())
        let service = PayabliService.makeWithChain(
            environment: .sandbox,
            readToken: { try await auth.currentAccessToken() },
            client: facts,
            session: StubURLProtocol.makeSession(),
            logger: logger
        )
        return AuthenticatedTransport(base: service, auth: auth, logger: logger)
    }

    func testEveryRequestCarriesTheClientHeader() async throws {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }

        _ = try await transport(auth: makeTestAuth(tokenProvider: { "tok" }))
            .perform(PayabliRequest(method: .get, path: "/api/v2/ping"))

        XCTAssertEqual(stub.requests.first?.value(forHTTPHeaderField: ClientHeader.name), expected)
    }

    func testAReplayAfterA401CarriesItAgain() async throws {
        let stub = RecordingStub { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer refreshed-token"
                ? (200, Data())
                : (401, Data())
        }
        stub.install()
        defer { stub.uninstall() }

        _ = try await transport(auth: makeTestAuth(tokenProvider: { "refreshed-token" }))
            .perform(PayabliRequest(method: .get, path: "/api/v2/ping"))

        XCTAssertEqual(stub.count, 2, "the 401 was not replayed")
        for request in stub.requests {
            XCTAssertEqual(request.value(forHTTPHeaderField: ClientHeader.name), expected)
        }
    }

    func testACallersOwnClientValueIsNotWhatReachesTheWire() async throws {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }

        _ = try await transport(auth: makeTestAuth(tokenProvider: { "tok" })).perform(
            PayabliRequest(method: .get, path: "/api/v2/ping", headers: ["x-pyb-client": "caller-supplied"])
        )

        XCTAssertEqual(stub.requests.first?.value(forHTTPHeaderField: ClientHeader.name), expected)
    }

    func testTheActivationIdHeaderACallerSetsReachesTheWireUnchangedBesideIt() async throws {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }

        _ = try await transport(auth: makeTestAuth(tokenProvider: { "tok" })).perform(
            PayabliRequest(method: .get, path: "/api/v2/ping", headers: ["X-Device-Id": "activation-id"])
        )

        XCTAssertEqual(stub.requests.first?.value(forHTTPHeaderField: "X-Device-Id"), "activation-id")
        XCTAssertEqual(stub.requests.first?.value(forHTTPHeaderField: ClientHeader.name), expected)
    }

    func testTheSessionsRequestsCarryItsDeviceIdentity() async throws {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }
        let session = try PayabliSession(
            config: PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "tok" }),
            urlSession: StubURLProtocol.makeSession(),
            deviceIdentity: DeviceIdentity { "0123456789abcdef0123456789abcdef" }
        )

        _ = try await session.transport.perform(PayabliRequest(method: .get, path: "/api/v2/ping"))

        let header = try XCTUnwrap(stub.requests.first?.value(forHTTPHeaderField: ClientHeader.name))
        XCTAssertTrue(header.hasPrefix(#"sdk-version="\#(PayabliCore.version)", platform=ios, "#), header)
        XCTAssertTrue(header.hasSuffix(#", device-id="0123456789abcdef0123456789abcdef""#), header)
    }
}

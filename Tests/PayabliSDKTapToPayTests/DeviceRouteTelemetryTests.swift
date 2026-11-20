@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// Every device route call reports one `ttp.device.<route>.completed`: `succeeded` on an answer read, `refused` with the
/// service's code when it answered no, `failed` when no usable answer arrived, and nothing when it was cancelled.
final class DeviceRouteTelemetryTests: XCTestCase {
    private let telemetryTransport = InMemoryTelemetryTransport()
    private let clock = ManualTelemetryClock()
    private let lifecycle = ManualAppLifecycle()

    func testEachRouteReportsItsOwnEventWithTheCatalogKeys() async throws {
        for route in [DeviceRoute.challenge, .register, .attest, .activate, .config] {
            let (client, telemetry) = makeClient(answering: .status(200, body: Self.success))

            _ = try await client.measured(route) { try await client.get(route, Self.request) }

            let events = try await sent(by: telemetry)
            XCTAssertEqual(events.map(\.event), ["ttp.device.\(route.rawValue).completed"])
            let properties = try XCTUnwrap(events.first?.properties)
            XCTAssertEqual(Set(properties.keys), ["outcome", "duration_ms"])
            XCTAssertEqual(properties["outcome"], "succeeded")
            XCTAssertNotNil(Int(properties["duration_ms"] ?? ""))
        }
    }

    func testARefusalTheServiceAnsweredReportsRefusedWithItsCode() async throws {
        let (client, telemetry) = makeClient(answering: .status(403, body: Self.decline(code: 403)))

        await assertThrows { _ = try await client.measured(.challenge) { try await Self.readRefusal(client.get(.challenge, Self.request)) }
        }

        let properties = try await onlyEvent(of: telemetry)
        XCTAssertEqual(properties, ["outcome": "refused", "code": "403", "duration_ms": properties["duration_ms"]!])
    }

    func testADeclineInsideASuccessfulStatusIsRefused() async throws {
        let (client, telemetry) = makeClient(answering: .status(200, body: Self.decline(code: 409)))

        await assertThrows { _ = try await client.measured(.attest) { try await Self.readRefusal(client.get(.attest, Self.request)) } }

        let properties = try await onlyEvent(of: telemetry)
        XCTAssertEqual(properties["outcome"], "refused")
        XCTAssertEqual(properties["code"], "409")
    }

    func testADeclineNamingNoCodeIsRefusedWithoutOne() async throws {
        let (client, telemetry) = makeClient(answering: .status(400, body: Data(#"{"isSuccess":false}"#.utf8)))

        await assertThrows { _ = try await client.measured(.register) { try await Self.readRefusal(client.get(.register, Self.request)) } }

        let properties = try await onlyEvent(of: telemetry)
        XCTAssertEqual(properties["outcome"], "refused")
        XCTAssertNil(properties["code"])
    }

    func testABare403OnConfigIsRefused() async throws {
        let (client, telemetry) = makeClient(answering: .status(403, body: Data()))

        await assertThrows { _ = try await client.measured(.config) { try await Self.readRefusal(client.get(.config, Self.request)) } }

        let properties = try await onlyEvent(of: telemetry)
        XCTAssertEqual(properties["outcome"], "refused")
        XCTAssertEqual(properties["code"], "403")
    }

    func testAServerFailureIsFailedWithoutACode() async throws {
        let (client, telemetry) = makeClient(answering: .status(503, body: Self.decline(code: 503)))

        await assertThrows { _ = try await client.measured(.register) { try await Self.readRefusal(client.get(.register, Self.request)) } }

        let properties = try await onlyEvent(of: telemetry)
        XCTAssertEqual(properties["outcome"], "failed")
        XCTAssertNil(properties["code"])
    }

    func testAnAnswerThatCannotBeReadIsFailed() async throws {
        let (client, telemetry) = makeClient(answering: .status(200, body: Data("not json".utf8)))

        await assertThrows { _ = try await client.measured(.config) { try await Self.readRefusal(client.get(.config, Self.request)) } }

        let properties = try await onlyEvent(of: telemetry)
        XCTAssertEqual(properties["outcome"], "failed")
        XCTAssertNil(properties["code"])
    }

    func testNoAnswerAtAllIsFailed() async throws {
        let (client, telemetry) = makeClient(answering: .error(URLError(.notConnectedToInternet)))

        await assertThrows { _ = try await client.measured(.activate) { try await client.get(.activate, Self.request) } }

        let properties = try await onlyEvent(of: telemetry)
        XCTAssertEqual(properties["outcome"], "failed")
        XCTAssertNil(properties["code"])
    }

    func testARefusedTokenIsFailed() async throws {
        let (client, telemetry) = makeClient(answering: .status(401, body: Data()))

        await assertThrows {
            _ = try await client.measured(.challenge) {
                _ = try await client.get(.challenge, Self.request)
                throw PinnedTokenRefusal()
            }
        }

        let properties = try await onlyEvent(of: telemetry)
        XCTAssertEqual(properties["outcome"], "failed")
    }

    func testARefusedTokensReportIsSentAtOnce() async {
        let (client, telemetry) = makeClient(answering: .status(401, body: Data()))

        await assertThrows {
            _ = try await client.measured(.challenge) {
                _ = try await client.get(.challenge, Self.request)
                throw PinnedTokenRefusal()
            }
        }
        await TelemetryRecorders.settled()
        await telemetry.settled()

        let events = await telemetryTransport.drainBatches().flatMap { $0 }
        XCTAssertEqual(events.map(\.event), ["ttp.device.challenge.completed"], "a failure does not wait for its batch")
    }

    func testACancelledCallReportsNothing() async throws {
        let (client, telemetry) = makeClient(answering: .error(CancellationError()))

        await assertThrows { _ = try await client.measured(.config) { try await client.get(.config, Self.request) } }

        let events = try await sent(by: telemetry)
        XCTAssertEqual(events, [], "a call its caller withdrew says nothing about the service")
    }

    func testAnEnrolmentReportsEachAttestationRouteItSent() async throws {
        let telemetry = makeTelemetry()
        StubURLProtocol.handler = { request in
            switch request.url!.path {
            case "/api/v2/device/taptopay/challenge":
                AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
            case "/api/v2/device/taptopay/register":
                AttestFixture.ok(request, ["deviceId": "dev_1"])
            default:
                AttestFixture.ok(request, ["ok": true])
            }
        }
        defer { StubURLProtocol.handler = nil }
        let (sut, _, _) = try AttestFixture.makeService()

        _ = try await sut.attest(entry: "myEntry")

        let events = try await sent(by: telemetry)
        XCTAssertEqual(
            events.map(\.event),
            ["ttp.device.challenge.completed", "ttp.device.register.completed", "ttp.device.attest.completed"]
        )
        XCTAssertEqual(events.map { $0.properties["outcome"] }, ["succeeded", "succeeded", "succeeded"])
    }

    func testAnAttestAcknowledgementThatCannotBeReadIsFailed() async throws {
        let telemetry = makeTelemetry()
        StubURLProtocol.handler = { request in
            switch request.url!.path {
            case "/api/v2/device/taptopay/challenge":
                AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
            case "/api/v2/device/taptopay/register":
                AttestFixture.ok(request, ["deviceId": "dev_1"])
            default:
                (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Data("not json".utf8)
                )
            }
        }
        defer { StubURLProtocol.handler = nil }
        let (sut, _, _) = try AttestFixture.makeService()

        await assertThrows { _ = try await sut.attest(entry: "myEntry") }

        let events = try await sent(by: telemetry)
        XCTAssertEqual(events.last?.event, "ttp.device.attest.completed")
        XCTAssertEqual(events.last?.properties["outcome"], "failed")
        XCTAssertNil(events.last?.properties["code"])
    }

    func testAnActivationAcknowledgementThatCannotBeReadIsFailed() async throws {
        let telemetry = makeTelemetry()
        StubURLProtocol.handler = { request in
            if request.url!.path == "/api/v2/device/taptopay/activate" {
                return (
                    HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                    Data("not json".utf8)
                )
            }
            return AttestFixture.ok(request, ["challengeId": "c_1", "challenge": "Y2hhbGxlbmdl"])
        }
        defer { StubURLProtocol.handler = nil }
        let storage = InMemorySecureStorage()
        try AttestFixture.seedBinding(entry: "myEntry", deviceId: "dev", keyId: "key", in: storage)
        let (sut, _, _) = try AttestFixture.makeService(storage: storage)

        await assertThrows {
            try await sut.activateDevice(activationCode: "123456", entry: "myEntry", activationId: "dev")
        }

        let events = try await sent(by: telemetry)
        XCTAssertEqual(events.last?.event, "ttp.device.activate.completed")
        XCTAssertEqual(events.last?.properties["outcome"], "failed")
    }

    func testARouteRefusalReadByTheRealClientIsRefusedWithItsCode() async throws {
        let telemetry = makeTelemetry()
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 404, httpVersion: "HTTP/1.1", headerFields: nil)!,
                Self.decline(code: 404)
            )
        }
        defer { StubURLProtocol.handler = nil }
        let (sut, _, _) = try AttestFixture.makeService()

        await assertThrows { _ = try await sut.attest(entry: "myEntry") }

        let properties = try await onlyEvent(of: telemetry)
        XCTAssertEqual(properties["outcome"], "refused")
        XCTAssertEqual(properties["code"], "404")
    }

    func testARefusedTokenWithADeclineBodyIsFailed() async throws {
        let telemetry = makeTelemetry()
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: nil)!,
                Self.decline(code: 401)
            )
        }
        defer { StubURLProtocol.handler = nil }
        let (sut, _, _) = try AttestFixture.makeService()

        await assertThrows { _ = try await sut.attest(entry: "myEntry") }

        let properties = try await onlyEvent(of: telemetry)
        XCTAssertEqual(properties["outcome"], "failed", "the token was refused, not the route")
        XCTAssertNil(properties["code"])
    }

    func testARateLimitIsFailed() async throws {
        let (client, telemetry) = makeClient(answering: .status(429, body: Self.decline(code: 429)))

        await assertThrows {
            _ = try await client.measured(.config) { try await Self.readRefusal(client.get(.config, Self.request)) }
        }

        let properties = try await onlyEvent(of: telemetry)
        XCTAssertEqual(properties["outcome"], "failed")
    }

    // MARK: - Fixtures

    private static let request = PayabliRequest(method: .get, path: "/api/v2/device/taptopay/config/e")
    private static let success = Data(#"{"isSuccess":true,"responseCode":1,"responseData":{}}"#.utf8)

    private static func decline(code: Int) -> Data {
        Data(#"{"isSuccess":false,"responseData":{"resultCode":\#(code),"resultText":"REASON-SENTINEL"}}"#.utf8)
    }

    /// Reads an answer as the route clients do: a decline or a failure status is a refusal, anything else unreadable throws.
    private static func readRefusal(_ response: PayabliResponse) throws -> PayabliResponse {
        if PayabliEnvelope.declineOutcome(from: response.body) != nil || response.statusCode >= 400 {
            throw TapToPayError(type: .unknown, reason: "refused", detail: nil, httpStatus: response.statusCode)
        }
        _ = try JSONSerialization.jsonObject(with: response.body)
        return response
    }

    private func makeClient(answering answer: FixedTransport.Answer) -> (DeviceRouteClient, TelemetryClient) {
        let telemetry = makeTelemetry()
        return (DeviceRouteClient(transport: FixedTransport(answer: answer)), telemetry)
    }

    /// A channel installed as the process recorder's, removed when the test ends.
    private func makeTelemetry() -> TelemetryClient {
        let telemetry = TelemetryClient(
            configuration: .init(entry: "test_entry", environment: "sandbox"),
            transport: telemetryTransport,
            sleep: clock.sleep,
            lifecycle: lifecycle,
            deviceId: { nil },
            queued: []
        )
        TelemetryRecorders.install(telemetry)
        addTeardownBlock { TelemetryRecorders.clear() }
        return telemetry
    }

    private func sent(by telemetry: TelemetryClient) async throws -> [SentEvent] {
        await TelemetryRecorders.settled()
        await telemetry.flush()
        let events = await telemetryTransport.drainBatches().flatMap { $0 }
        return events.map { SentEvent(event: $0.event, properties: $0.properties) }
    }

    private func onlyEvent(of telemetry: TelemetryClient) async throws -> [String: String] {
        let events = try await sent(by: telemetry)
        XCTAssertEqual(events.count, 1)
        return try XCTUnwrap(events.first?.properties)
    }

    private func assertThrows(_ work: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await work()
            XCTFail("expected the call to throw", file: file, line: line)
        } catch {}
    }
}

private struct SentEvent: Equatable {
    let event: String
    let properties: [String: String]
}

/// Answers every request the same way.
private struct FixedTransport: PayabliTransport {
    enum Answer: Sendable {
        case status(Int, body: Data)
        case error(any Error)
    }

    let answer: Answer

    func perform(_: PayabliRequest) async throws -> PayabliResponse {
        switch answer {
        case let .status(code, body): PayabliResponse(statusCode: code, headers: [:], body: body)
        case let .error(error): throw error
        }
    }

    func performV2<T: Decodable & Sendable>(_: PayabliRequest, decoding _: T.Type) async throws -> PayabliV2Envelope<T> {
        throw URLError(.unsupportedURL)
    }
}

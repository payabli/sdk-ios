@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// Card-present setup settles every failure in one step: an error the SDK did not expect is its internal error naming the
/// type, a re-arm reports its start and success, and `ttp.initialize.failed` carries the service's code when it had one.
@available(iOS 16.7, *)
@MainActor
final class SetupSettleTests: XCTestCase {
    private struct HostThrew: LocalizedError {
        var errorDescription: String? {
            "MESSAGE-SENTINEL"
        }
    }

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = TapToPayReportsTests.configHandler(status: 200)
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testAForeignErrorWhileFetchingTheConfigurationIsTheSDKsInternalError() async throws {
        let (ttp, _, attestation, _) = try makeTTP()
        attestation.assertionFailure = HostThrew()

        try await assertInternal { try await ttp.initialize() }
        XCTAssertEqual(ttp.sessionState, .failed(reason: .sdkInternalError))
    }

    func testAForeignErrorWhileConfiguringTheReaderIsTheSDKsInternalError() async throws {
        let (ttp, provider, _, _) = try makeTTP()
        provider.configureResult = .failure(HostThrew())

        try await assertInternal { try await ttp.initialize() }
        XCTAssertEqual(ttp.sessionState, .failed(reason: .sdkInternalError))
    }

    func testARearmReportsItsStartAndItsSuccess() async throws {
        let (ttp, provider, _, transport) = try makeTTP()
        provider.prepareReaderResult = .failure(PayabliTTPError.readerUnavailable(reason: "busy"))
        _ = try? await ttp.initialize()
        provider.prepareReaderResult = .success(())

        try await ttp.reinitialize()
        await ttp.reports.sent()
        await ttp.session.telemetry.flush()

        let events = await transport.batches.flatMap { $0 }.filter { $0.event.hasPrefix("ttp.reinitialize.") }
        XCTAssertEqual(events.map(\.event), ["ttp.reinitialize.started", "ttp.reinitialize.succeeded"])
        XCTAssertEqual(events.first?.properties, [:])
        XCTAssertEqual(Set(events.last?.properties.keys ?? [:].keys), ["duration_ms"])
    }

    func testAFailedInitializeCarriesTheServicesCodeOnlyWhenItHadOne() async throws {
        let refused = try makeTTP()
        StubURLProtocol.handler = { request in
            (
                HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1", headerFields: nil)!,
                Data(#"{"isSuccess":false,"responseData":{"resultCode":404,"resultText":"x"}}"#.utf8)
            )
        }
        _ = try? await refused.0.initialize()
        let refusedEvent = try await failedEvent(refused.0, refused.3)
        XCTAssertEqual(refusedEvent["code"], "404")
        XCTAssertNil(refusedEvent["failure_type"])

        let foreign = try makeTTP()
        foreign.1.configureResult = .failure(HostThrew())
        StubURLProtocol.handler = TapToPayReportsTests.configHandler(status: 200)
        _ = try? await foreign.0.initialize()
        let foreignEvent = try await failedEvent(foreign.0, foreign.3)
        XCTAssertNil(foreignEvent["code"])
        XCTAssertEqual(foreignEvent["failure_type"], "HostThrew")
    }

    // MARK: - Fixtures

    private func assertInternal(file: StaticString = #filePath, line: UInt = #line, _ call: () async throws -> Void) async throws {
        do {
            try await call()
            XCTFail("expected the call to fail", file: file, line: line)
        } catch let error as TapToPayError {
            XCTAssertEqual(error.code, 1018, file: file, line: line)
            XCTAssertEqual((error.underlying as? RedactedCause)?.simpleTypeName, "HostThrew", file: file, line: line)
            XCTAssertFalse("\(error)".contains("MESSAGE-SENTINEL"), file: file, line: line)
            XCTAssertFalse(error.localizedDescription.contains("MESSAGE-SENTINEL"), file: file, line: line)
        }
    }

    private func failedEvent(_ ttp: PayabliTTP, _ transport: InMemoryTelemetryTransport) async throws -> [String: String] {
        await ttp.reports.sent()
        await ttp.session.telemetry.flush()
        let failed = await transport.batches.flatMap { $0 }.filter { $0.event == "ttp.initialize.failed" }
        XCTAssertEqual(failed.count, 1)
        return try XCTUnwrap(failed.first?.properties)
    }

    private func makeTTP() throws -> (
        PayabliTTP, MockTapToPayProvider, MockDeviceAttestationService, InMemoryTelemetryTransport
    ) {
        let provider = MockTapToPayProvider()
        let attestation = MockDeviceAttestationService()
        let transport = InMemoryTelemetryTransport()
        let ttp = PayabliTTP(
            config: try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" }),
            provider: provider,
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession(),
            telemetry: transport
        )
        return (ttp, provider, attestation, transport)
    }
}

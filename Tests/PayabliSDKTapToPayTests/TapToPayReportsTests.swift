@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// `initialize` reports once per run it owns: a start, then one ending, carrying none of the text a host's error
/// does.
@available(iOS 16.7, *)
@MainActor
final class TapToPayReportsTests: XCTestCase {
    /// The keys `ttp.initialize.failed` may carry. `error_number` is the code the host was told.
    private static let failedKeys: Set<String> = ["outcome", "code", "duration_ms", "failure_type", "error_number"]
    private static let sentinel = "REASON-SENTINEL"

    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = Self.configHandler(status: 200)
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testASuccessfulInitializeReportsAStartAndASuccess() async throws {
        let (ttp, _, _, transport) = try makeTTP()

        try await ttp.initialize()
        await ttp.reports.sent()
        await ttp.session.telemetry.flush()

        let events = await sent(transport)
        XCTAssertEqual(
            events.map(\.event),
            ["ttp.initialize.started", "ttp.attestation.started", "ttp.attestation.succeeded", "ttp.initialize.succeeded"]
        )
        let succeeded = try XCTUnwrap(events.last)
        XCTAssertEqual(Set(succeeded.properties.keys), ["duration_ms"])
        XCTAssertNotNil(Int(succeeded.properties["duration_ms"] ?? ""))
    }

    func testAnAttestationRefusalTheSessionRenewsWaitsForItsBatch() async throws {
        let (ttp, _, _, transport) = try makeTTP()

        ttp.reports.attestationFailed(PinnedTokenRefusal(), after: .zero)
        await ttp.reports.sent()
        let whileHeld = await ttp.session.telemetry.bufferedCount
        ttp.reports.releaseHeld()
        await ttp.reports.sent()

        XCTAssertEqual(whileHeld, 0, "held until the renewal, so no batch it fills can carry the token being renewed")
        let buffered = await ttp.session.telemetry.bufferedCount
        XCTAssertEqual(buffered, 1, "released into the batch")
        let sent = await transport.batches
        XCTAssertTrue(sent.isEmpty, "and not sent at once")
    }

    func testAnyOtherAttestationFailureIsSentAtOnce() async throws {
        let (ttp, _, _, transport) = try makeTTP()

        ttp.reports.attestationFailed(PayabliTTPError.attestationFailed(reason: Self.sentinel), after: .zero)
        await ttp.reports.sent()

        let sent = await sent(transport).map(\.event)
        XCTAssertEqual(sent, ["ttp.attestation.failed"])
    }

    func testEveryFailurePathReportsOneFailureWithTheNumberTheHostWasTold() async throws {
        let paths: [(String, (MockTapToPayProvider, MockDeviceAttestationService) -> Void)] = [
            ("eligibility", { provider, _ in
                provider.eligibility = .failure(.readerSetupFailed(reason: Self.sentinel))
            }),
            ("attestation", { _, attestation in
                attestation.attestResult = .failure(PayabliTTPError.attestationFailed(reason: Self.sentinel))
            }),
            ("pending with no registration stored", { _, attestation in
                attestation.attestResult = .failure(PayabliTTPError.devicePendingActivation)
            }),
            ("configure", { provider, _ in
                provider.configureResult = .failure(PayabliTTPError.readerCredentialsUnusable)
            }),
            ("prepare", { provider, _ in
                provider.prepareReaderResult = .failure(PayabliTTPError.readerSetupFailed(reason: Self.sentinel))
            })
        ]

        for (path, arrange) in paths {
            let (ttp, provider, attestation, transport) = try makeTTP()
            arrange(provider, attestation)
            try await assertOneReportedFailure(ttp, transport, path)
        }
    }

    func testAConfigurationTheServiceRefusesReportsOneFailure() async throws {
        StubURLProtocol.handler = Self.configHandler(status: 500)
        let (ttp, _, attestation, transport) = try makeTTP()
        attestation.isAlreadyAttested = true

        try await assertOneReportedFailure(ttp, transport, "config fetch")
    }

    func testADismissedSetupSheetReportsACancelInTheNextBatchAndNoFailure() async throws {
        let (ttp, provider, _, transport) = try makeTTP()
        provider.prepareReaderResult = .failure(PayabliTTPError.readerSetupFailed(
            reason: "\(PayabliTTPError.cancellationReasonPrefix) \(Self.sentinel)"
        ))

        try await initializeToItsEnd(ttp, expecting: .userCancelled)
        await ttp.reports.sent()
        let beforeTheBatch = await sent(transport).map(\.event)
        XCTAssertFalse(beforeTheBatch.contains("ttp.initialize.cancelled"), "a choice waits for the batch")
        await ttp.session.telemetry.flush()

        let events = await sent(transport)
        XCTAssertFalse(events.contains { $0.event == "ttp.initialize.failed" }, "\(events.map(\.event))")
        let cancelled = events.filter { $0.event == "ttp.initialize.cancelled" }
        XCTAssertEqual(cancelled.count, 1)
        XCTAssertEqual(cancelled.first.map { Set($0.properties.keys) }, ["duration_ms"])
        XCTAssertNotNil(Int(cancelled.first?.properties["duration_ms"] ?? ""))
    }

    func testASetupWaitingOnAPersonReportsPendingWithItsStateInTheNextBatch() async throws {
        let paths: [(String, PayabliErrorType, (MockTapToPayProvider, MockDeviceAttestationService) -> Void)] = [
            ("pending_activation", .devicePendingActivation, { _, attestation in
                attestation.pendingRegistration = "dev"
                attestation.attestResult = .failure(PayabliTTPError.devicePendingActivation)
            }),
            ("pending_terms", .termsNotAccepted, { provider, _ in
                provider.prepareReaderResult = .failure(PayabliTTPError.termsNotAccepted)
            })
        ]

        for (state, told, arrange) in paths {
            let (ttp, provider, attestation, transport) = try makeTTP()
            arrange(provider, attestation)

            try await initializeToItsEnd(ttp, expecting: told)
            await ttp.reports.sent()
            let beforeTheBatch = await sent(transport).map(\.event)
            XCTAssertFalse(beforeTheBatch.contains("ttp.initialize.pending"), "\(state): waits for the batch")
            await ttp.session.telemetry.flush()

            let events = await sent(transport)
            XCTAssertFalse(events.contains { $0.event == "ttp.initialize.failed" }, "\(state): \(events.map(\.event))")
            let pending = events.filter { $0.event == "ttp.initialize.pending" }
            XCTAssertEqual(pending.count, 1, state)
            XCTAssertEqual(pending.first?.properties["state"], state)
            XCTAssertEqual(pending.first.map { Set($0.properties.keys) }, ["state", "duration_ms"], state)
        }
    }

    func testAWithdrawnInitializeReportsNoFailure() async throws {
        let (ttp, _, attestation, transport) = try makeTTP()
        attestation.attestResult = .failure(CancellationError())

        do {
            try await ttp.initialize()
            XCTFail("expected a cancellation")
        } catch {}
        await ttp.reports.sent()
        await ttp.session.telemetry.flush()

        let events = await sent(transport)
        XCTAssertFalse(events.contains { $0.event == "ttp.initialize.failed" }, "\(events.map(\.event))")
    }

    func testACallerThatJoinsARunInFlightAddsNoReport() async throws {
        StubURLProtocol.handler = Self.configHandler(status: 500)
        let (ttp, _, attestation, transport) = try makeTTP()
        attestation.isAlreadyAttested = true

        async let first: Void = ttp.initialize()
        async let second: Void = ttp.initialize()
        _ = try? await first
        _ = try? await second
        await ttp.reports.sent()
        await ttp.session.telemetry.flush()

        let events = await sent(transport).map(\.event)
        XCTAssertEqual(events.filter { $0 == "ttp.initialize.started" }.count, 1, "\(events)")
        XCTAssertEqual(events.filter { $0 == "ttp.initialize.failed" }.count, 1, "\(events)")
    }

    func testAReportQueuedBehindASlowSendKeepsTheTimeItWasMade() async throws {
        let transport = HeldTelemetryTransport()
        let client = TelemetryClient(
            configuration: .init(entry: "e", environment: "sandbox"),
            transport: transport,
            sleep: ManualTelemetryClock().sleep,
            lifecycle: ManualAppLifecycle()
        )
        let reports = TapToPayReports(telemetry: client)

        reports.initializeEnded(PayabliTTPError.readerCredentialsUnusable, after: .milliseconds(5))
        await transport.waitUntilHeld()
        reports.initializeStarted()
        let made = Date()
        try await Task.sleep(for: .milliseconds(200))
        await transport.release()
        await reports.sent()
        await client.flush()

        let sent = await transport.sent
        let started = try XCTUnwrap(sent.first { $0.event == "ttp.initialize.started" })
        XCTAssertLessThanOrEqual(started.timestamp, made)
    }

    // MARK: - Helpers

    /// Runs `initialize` to its failure and reads what reached the transport without flushing it, so the
    /// failure's own send is what is proved.
    private func assertOneReportedFailure(
        _ ttp: PayabliTTP,
        _ transport: InMemoryTelemetryTransport,
        _ path: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        var told: TapToPayError?
        do {
            try await ttp.initialize()
            XCTFail("\(path): expected a failure", file: file, line: line)
        } catch {
            told = error as? TapToPayError
        }
        let code = try XCTUnwrap(told?.code, "\(path)", file: file, line: line)
        await ttp.reports.sent()

        let failures = await sent(transport).filter { $0.event == "ttp.initialize.failed" }
        XCTAssertEqual(failures.count, 1, "\(path): sent at once, and once", file: file, line: line)
        guard let failed = failures.first else { return }
        XCTAssertEqual(failed.properties["error_number"], String(code), "\(path)", file: file, line: line)
        XCTAssertEqual(failed.properties["outcome"], "failed", "\(path)", file: file, line: line)
        XCTAssertNotNil(Int(failed.properties["duration_ms"] ?? ""), "\(path)", file: file, line: line)
        XCTAssertTrue(
            Set(failed.properties.keys).isSubset(of: Self.failedKeys),
            "\(path): \(failed.properties.keys.sorted())",
            file: file,
            line: line
        )
        for value in failed.properties.values {
            XCTAssertFalse(value.contains(Self.sentinel), "\(path): \(value)", file: file, line: line)
        }
    }

    private func initializeToItsEnd(
        _ ttp: PayabliTTP,
        expecting type: PayabliErrorType,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        do {
            try await ttp.initialize()
            XCTFail("expected \(type)", file: file, line: line)
        } catch let told as TapToPayError {
            XCTAssertEqual(told.type, type, file: file, line: line)
        }
    }

    private func sent(_ transport: InMemoryTelemetryTransport) async -> [TelemetryEvent] {
        await transport.batches.flatMap { $0 }
    }

    private func makeTTP() throws -> (
        PayabliTTP, MockTapToPayProvider, MockDeviceAttestationService, InMemoryTelemetryTransport
    ) {
        let config = try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" })
        let provider = MockTapToPayProvider()
        let attestation = MockDeviceAttestationService()
        let transport = InMemoryTelemetryTransport()
        let ttp = PayabliTTP(
            config: config,
            provider: provider,
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession(),
            telemetry: transport
        )
        return (ttp, provider, attestation, transport)
    }

    /// A configuration envelope for any request, or a bare failure status.
    static func configHandler(
        status: Int,
        credentials: [String: String] = ["secretKey": "s", "apiKey": "a", "merchantId": "m", "terminalId": "t"]
    ) -> StubURLProtocol.Handler {
        { request in
            let body: [String: Any] = [
                "responseCode": 1,
                "isSuccess": true,
                "responseData": ["credentials": credentials],
                "paymentToken": "payment_tok"
            ]
            let data = status == 200 ? try JSONSerialization.data(withJSONObject: body) : Data()
            return (HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Type": "application/json"]
            )!, data)
        }
    }
}

/// Holds the first batch until released, so a report can be queued behind a send still in flight.
private actor HeldTelemetryTransport: TelemetryTransport {
    private(set) var sent: [TelemetryEvent] = []
    private var held: CheckedContinuation<Void, Never>?
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []
    private var released = false

    func send(_ batch: [TelemetryEvent], droppedSinceLastSend: Int) async -> Bool {
        sent += batch
        guard !released else { return true }
        await withCheckedContinuation { continuation in
            held = continuation
            heldWaiters.forEach { $0.resume() }
            heldWaiters.removeAll()
        }
        return true
    }

    func waitUntilHeld() async {
        guard held == nil else { return }
        await withCheckedContinuation { heldWaiters.append($0) }
    }

    func release() {
        released = true
        held?.resume()
        held = nil
    }
}

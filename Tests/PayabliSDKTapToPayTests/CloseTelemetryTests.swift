@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// Every close reports `ttp.close.started`, then `ttp.close.succeeded` or `ttp.close.failed`, as a charge's own close
/// (`origin` `charge`) or through `closeCapturedCharge` (`origin` `retry`). A failure says what the host was told.
@available(iOS 16.7, *)
@MainActor
final class CloseTelemetryTests: XCTestCase {
    private static let wire = CloseWire()
    private static let opened = "TXN-OPENED"
    private static let sale = PayabliTTPPaymentDetails(amount: 1, currency: .usd)
    private static let processorHasNoRecord = "Unable to locate the transaction with the payment processor"
    private static let failedKeys: Set<String> = [
        "outcome", "code", "duration_ms", "error_number", "failure_type", "origin", "capture", "http_status", "reason"
    ]
    private let keys = ChargeKeyStore()
    private let held = HeldPayments()
    private let live = Liveness()

    override func setUp() {
        super.setUp()
        Self.wire.reset()
        StubURLProtocol.handler = Self.wire.handle
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        Self.wire.reset()
        super.tearDown()
    }

    // MARK: - The charge's own close

    func testAChargeWhoseCloseLandsReportsItsCloseAsTheCharges() async throws {
        let (terminal, transport) = try await makeReadyTerminal()

        _ = try await terminal.charge(paymentDetails: Self.sale)

        let closes = await reported(terminal, transport)
        XCTAssertEqual(closes.map(\.event), ["ttp.close.started", "ttp.close.succeeded"])
        XCTAssertEqual(closes.map { $0.properties["origin"] }, ["charge", "charge"])
        XCTAssertNotNil(Int(closes.last?.properties["duration_ms"] ?? ""), "\(closes)")
    }

    func testAChargeCancelledWhileItsCloseIsInFlightReportsNoFailedClose() async throws {
        let (terminal, transport) = try await makeReadyTerminal()
        Self.wire.holdUpdates()

        let charging = Task { _ = try await terminal.charge(paymentDetails: Self.sale) }
        await Self.wire.waitUntilAnUpdateArrives()
        charging.cancel()
        Self.wire.release()
        _ = try? await charging.value

        let closes = await reported(terminal, transport)
        XCTAssertEqual(closes.map(\.event), ["ttp.close.started"], "\(closes.map(\.properties))")
    }

    func testAChargeWhoseCloseFailsReportsWhatTheHostWasTold() async throws {
        let (terminal, transport) = try await makeReadyTerminal()
        Self.wire.script(updates: [500])

        let told = await Self.failure { _ = try await terminal.charge(paymentDetails: Self.sale) }

        let failed = try await oneFailure(terminal, transport)
        XCTAssertEqual(told?.capture, .charged, "the fixture itself is broken if this fails")
        XCTAssertEqual(failed.properties["origin"], "charge")
        XCTAssertEqual(failed.properties["capture"], "charged")
        XCTAssertEqual(failed.properties["http_status"], "500")
        XCTAssertEqual(failed.properties["error_number"], String(PayabliErrorType.paymentNotClosed.number))
        XCTAssertEqual(failed.properties["outcome"], "failed")
        XCTAssertEqual(failed.properties["failure_type"], "PayabliPaymentError")
        XCTAssertNil(failed.properties["reason"], "only the no-record refusal carries a reason")
    }

    func testADeclinedCardWhoseCloseFailsReportsItNotCharged() async throws {
        let (terminal, transport) = try await makeReadyTerminal(read: .declined)
        Self.wire.script(updates: [500])

        _ = await Self.failure { _ = try await terminal.charge(paymentDetails: Self.sale) }

        let failed = try await oneFailure(terminal, transport)
        XCTAssertEqual(failed.properties["capture"], "not_charged")
        XCTAssertEqual(failed.properties["outcome"], "failed", "a close is never a decline")
    }

    func testAFailedReadsCloseTheProcessorHasNoRecordOfReportsTheReasonAndNothingCharged() async throws {
        let (terminal, transport) = try await makeReadyTerminal(readFailure: PayabliTTPError.nfcFailed(reason: "tap failed"))
        Self.wire.script(updates: [400], detail: Self.processorHasNoRecord)

        let told = await Self.failure { _ = try await terminal.charge(paymentDetails: Self.sale) }

        let failed = try await oneFailure(terminal, transport)
        XCTAssertEqual(told?.type, .paymentNotTaken, "the fixture itself is broken if this fails")
        XCTAssertEqual(failed.properties["origin"], "charge")
        XCTAssertEqual(failed.properties["reason"], "processor_no_record")
        XCTAssertEqual(failed.properties["capture"], "not_charged")
        XCTAssertEqual(failed.properties["http_status"], "400")
    }

    func testAFailedReadsCloseNothingAnsweredCarriesNoStatus() async throws {
        let (terminal, transport) = try await makeReadyTerminal(readFailure: PayabliTTPError.nfcFailed(reason: "tap failed"))
        StubURLProtocol.handler = { request in
            if request.url?.path.contains("/MoneyIn/update/") == true {
                throw URLError(.notConnectedToInternet)
            }
            return try Self.wire.handle(request)
        }

        let told = await Self.failure { _ = try await terminal.charge(paymentDetails: Self.sale) }

        let failed = try await oneFailure(terminal, transport)
        XCTAssertNil(failed.properties["http_status"], "\(failed.properties)")
        XCTAssertNil(failed.properties["reason"])
        XCTAssertEqual(failed.properties["capture"], told.map { Self.spelled($0.capture) })
        XCTAssertNotNil(failed.properties["failure_type"])
    }

    func testAChargeRefusedAsRetiredReportsItsCloseNotCharged() async throws {
        let (terminal, transport) = try await makeReadyTerminal()
        StubURLProtocol.handler = { [live] request in
            if request.url?.path.contains("/MoneyIn/initiate") == true {
                live.value = false
            }
            return try Self.wire.handle(request)
        }
        Self.wire.script(updates: [500])

        let told = await Self.failure { _ = try await terminal.charge(paymentDetails: Self.sale) }

        let failed = try await oneFailure(terminal, transport)
        XCTAssertEqual(told?.type, .sessionNotInitialized, "the fixture itself is broken if this fails")
        XCTAssertEqual(failed.properties["origin"], "charge")
        XCTAssertEqual(failed.properties["capture"], "not_charged")
    }

    // MARK: - closeCapturedCharge

    func testACloseThatLandsReportsItsCloseAsARetry() async throws {
        let (terminal, transport) = try await makeReadyTerminal()

        try await terminal.closeCapturedCharge(paymentTransId: "TXN-EARLIER")

        let closes = await reported(terminal, transport)
        XCTAssertEqual(closes.map(\.event), ["ttp.close.started", "ttp.close.succeeded"])
        XCTAssertEqual(closes.map { $0.properties["origin"] }, ["retry", "retry"])
        XCTAssertNotNil(Int(closes.last?.properties["duration_ms"] ?? ""), "\(closes)")
    }

    func testAFailedCloseOfAPaymentNotHeldReportsItUnknown() async throws {
        let (terminal, transport) = try await makeReadyTerminal()
        Self.wire.script(updates: [500])

        _ = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: "TXN-EARLIER") }

        let failed = try await oneFailure(terminal, transport)
        XCTAssertEqual(failed.properties["origin"], "retry")
        XCTAssertEqual(failed.properties["capture"], "unknown")
        XCTAssertEqual(failed.properties["http_status"], "500")
        XCTAssertEqual(failed.properties["error_number"], String(PayabliErrorType.paymentNotClosed.number))
        XCTAssertEqual(failed.properties["failure_type"], "PayabliPaymentError")
    }

    func testAFailedCloseOfAHeldPaymentReportsTheReadersCapture() async throws {
        let (terminal, transport) = try await makeReadyTerminal()
        Self.wire.script(updates: [500])
        _ = await Self.failure { _ = try await terminal.charge(paymentDetails: Self.sale) }

        let told = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: Self.opened) }

        let retries = try await failures(terminal, transport).filter { $0.properties["origin"] == "retry" }
        XCTAssertEqual(told?.capture, .charged, "the fixture itself is broken if this fails")
        XCTAssertEqual(retries.count, 1, "\(retries)")
        XCTAssertEqual(retries.first?.properties["capture"], "charged")
    }

    func testACloseTheCallerMayNotMakeReportsTheNumberItWasTold() async throws {
        let (terminal, transport) = try await makeReadyTerminal()
        Self.wire.script(updates: [400], refusal: "E9001")

        let told = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: "TXN-EARLIER") }

        let failed = try await oneFailure(terminal, transport)
        XCTAssertEqual(told?.type, .permissionDenied, "the fixture itself is broken if this fails")
        XCTAssertEqual(failed.properties["error_number"], String(PayabliErrorType.permissionDenied.number))
        XCTAssertEqual(failed.properties["http_status"], "400")
        XCTAssertEqual(failed.properties["code"], "E9001")
    }

    func testAFailedCloseCarriesOnlyItsDeclaredKeysAndNoText() async throws {
        let (terminal, transport) = try await makeReadyTerminal()
        Self.wire.script(updates: [500], refusal: "SENTINEL")

        _ = await Self.failure { try await terminal.closeCapturedCharge(paymentTransId: "TXN-EARLIER") }

        let failed = try await oneFailure(terminal, transport)
        XCTAssertTrue(Set(failed.properties.keys).isSubset(of: Self.failedKeys), "\(failed.properties.keys.sorted())")
        XCTAssertFalse(failed.properties.values.contains { $0.contains("refused") }, "\(failed.properties)")
        XCTAssertFalse(failed.properties.values.contains { $0.contains("TXN-") }, "\(failed.properties)")
    }

    // MARK: - Helpers

    /// The close events the terminal reported, in the order they reached the transport, after every report was sent.
    private func reported(_ terminal: PayabliTTP, _ transport: InMemoryTelemetryTransport) async -> [TelemetryEvent] {
        await terminal.reports.sent()
        await terminal.session.telemetry.flush()
        return await transport.batches.flatMap { $0 }.filter { $0.event.hasPrefix("ttp.close.") }
    }

    private func failures(
        _ terminal: PayabliTTP,
        _ transport: InMemoryTelemetryTransport
    ) async throws -> [TelemetryEvent] {
        let closes = await reported(terminal, transport)
        XCTAssertEqual(
            closes.filter { $0.event == "ttp.close.started" }.count,
            closes.filter { $0.event != "ttp.close.started" }.count,
            "every close that started ended once: \(closes.map(\.event))"
        )
        return closes.filter { $0.event == "ttp.close.failed" }
    }

    private func oneFailure(
        _ terminal: PayabliTTP,
        _ transport: InMemoryTelemetryTransport,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws -> TelemetryEvent {
        let failed = try await failures(terminal, transport)
        XCTAssertEqual(failed.count, 1, "\(failed)", file: file, line: line)
        return try XCTUnwrap(failed.first, file: file, line: line)
    }

    private static func spelled(_ capture: PayabliTTPCapture) -> String {
        switch capture {
        case .notCharged: "not_charged"
        case .unknown: "unknown"
        case .charged: "charged"
        }
    }

    private func makeReadyTerminal(
        read outcome: CardReadOutcome = .approved,
        readFailure: Error? = nil
    ) async throws -> (PayabliTTP, InMemoryTelemetryTransport) {
        let provider = MockTapToPayProvider()
        provider.readingResult = readFailure.map { .failure($0) }
            ?? .success(CardReadResult(provider: "mock", encryptedPayload: Data(), outcome: outcome))
        let transport = InMemoryTelemetryTransport()
        let config = try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "token" })
        let terminal = PayabliTTP(
            config: config,
            provider: provider,
            attestation: MockDeviceAttestationService(),
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession(),
            telemetry: transport,
            isLive: { [live] in live.value },
            chargeKeys: keys,
            heldPayments: held
        )
        try await terminal.initialize()
        XCTAssertEqual(terminal.sessionState, .ready, "the fixture itself is broken if this fails")
        return (terminal, transport)
    }

    private static func failure(_ body: @MainActor () async throws -> Void) async -> TapToPayError? {
        do {
            try await body()
            XCTFail("expected a failure")
        } catch let failure as TapToPayError {
            return failure
        } catch {
            XCTFail("expected a TapToPayError, got \(error)")
        }
        return nil
    }
}

/// Whether the terminal's session is still the installed one, as a case sets it.
private final class Liveness: @unchecked Sendable {
    private let lock = NSLock()
    private var live = true

    var value: Bool {
        get { lock.withLock { live } }
        set { lock.withLock { live = newValue } }
    }
}

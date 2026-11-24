@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// Every move of the card-present session goes through one writer, which reports `ttp.session.stateChanged` with
/// `from` and `to`, and `reason` only when the move was to failed.
@available(iOS 16.7, *)
@MainActor
final class SessionStateReportTests: XCTestCase {
    func testEachMoveIsReportedWithBothEnds() throws {
        let manager = SessionManager()
        var moves: [(String, String)] = []
        manager.onMove = { from, to in moves.append((from.diagnosticName, to.diagnosticName)) }

        try manager.advance(to: .attestingDevice)
        try manager.advance(to: .fetchingConfig)

        XCTAssertEqual(moves.map(\.0), ["idle", "attesting_device"])
        XCTAssertEqual(moves.map(\.1), ["attesting_device", "fetching_config"])
    }

    func testProgressWithinOneStateIsNotAMove() throws {
        let manager = SessionManager()
        try manager.advance(to: .attestingDevice)
        try manager.advance(to: .fetchingConfig)
        try manager.advance(to: .initializingReader(percent: nil))
        var count = 0
        manager.onMove = { _, _ in count += 1 }

        manager.recordConfigurationProgress(40)
        manager.recordConfigurationProgress(80)

        XCTAssertEqual(count, 0)
    }

    func testAChargeReportsItsStartAndItsEndAndNotItsActivities() throws {
        let manager = try Self.readyManager()
        var moves: [String] = []
        manager.onMove = { from, to in moves.append("\(from.diagnosticName) -> \(to.diagnosticName)") }

        let charge = try XCTUnwrap(manager.beginCharge())
        for activity in [TapToPayChargeActivity.waitingForCard, .cardDetected, .pinEntryRequested, .pinEntryCompleted, .closing] {
            manager.recordChargeActivity(activity, for: charge)
        }
        manager.endCharge(charge)

        XCTAssertEqual(moves, ["ready -> charging", "charging -> ready"])
    }

    func testAFailedChargeReportsItsMoveToFailed() throws {
        let manager = try Self.readyManager()
        var moves: [String] = []
        manager.onMove = { from, to in moves.append("\(from.diagnosticName) -> \(to.diagnosticName)") }

        let charge = try XCTUnwrap(manager.beginCharge())
        manager.recordChargeActivity(.waitingForCard, for: charge)
        manager.failCharge(.sdkInternalError, for: charge)

        XCTAssertEqual(moves, ["ready -> charging", "charging -> failed"])
    }

    func testAFailureOnAFailedSessionForAnotherReasonIsAMove() {
        let manager = SessionManager()
        var moves: [String] = []
        manager.onMove = { from, to in moves.append("\(from.diagnosticName) -> \(to.diagnosticName)") }

        manager.markError(PayabliTTPError.readerUnavailable(reason: "busy"), registration: .none)
        manager.markError(PayabliTTPError.readerUnavailable(reason: "busy"), registration: .none)
        manager.markError(PayabliTTPError.configFailed(reason: "x"), registration: .none)

        XCTAssertEqual(moves, ["idle -> failed", "failed -> failed"])
        XCTAssertEqual(manager.sessionState, .failed(reason: .configurationRejected))
    }

    func testAPendingAnswerForAnotherRegistrationLandsFromTheNextRun() throws {
        let manager = SessionManager()
        try manager.advance(to: .fetchingConfig)
        var moves: [String] = []
        manager.onMove = { from, to in moves.append("\(from.diagnosticName) -> \(to.diagnosticName)") }

        manager.markError(PayabliTTPError.devicePendingActivation(httpStatus: 403), registration: .held(activationId: "dev_a"))
        manager.markError(PayabliTTPError.devicePendingActivation(httpStatus: 403), registration: .held(activationId: "dev_b"))
        XCTAssertEqual(manager.sessionState, .pendingActivation(activationId: "dev_a"))

        try manager.advance(to: .attestingDevice)
        try manager.advance(to: .fetchingConfig)
        manager.markError(PayabliTTPError.devicePendingActivation(httpStatus: 403), registration: .held(activationId: "dev_b"))

        XCTAssertEqual(moves, [
            "fetching_config -> pending_activation",
            "pending_activation -> attesting_device",
            "attesting_device -> fetching_config",
            "fetching_config -> pending_activation"
        ])
        XCTAssertEqual(manager.sessionState, .pendingActivation(activationId: "dev_b"))
    }

    func testAMoveToFailedSaysWhyAndNoOtherMoveDoes() async throws {
        let transport = InMemoryTelemetryTransport()
        let provider = MockTapToPayProvider()
        provider.prepareReaderResult = .failure(PayabliTTPError.readerUnavailable(reason: "busy"))
        StubURLProtocol.handler = TapToPayReportsTests.configHandler(status: 200)
        defer { StubURLProtocol.handler = nil }
        let ttp = PayabliTTP(
            config: try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" }),
            provider: provider,
            attestation: MockDeviceAttestationService(),
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession(),
            telemetry: transport
        )

        _ = try? await ttp.initialize()
        await TelemetryRecorders.settled()
        await ttp.session.telemetry.flush()

        let moves = await transport.batches.flatMap { $0 }.filter { $0.event == "ttp.session.stateChanged" }
        let failed = try XCTUnwrap(moves.last)
        XCTAssertEqual(failed.properties, ["from": "initializing_reader", "to": "failed", "reason": "service_unavailable"])
        for move in moves.dropLast() {
            XCTAssertEqual(Set(move.properties.keys), ["from", "to"], "\(move.properties)")
        }
        XCTAssertFalse(moves.dropLast().isEmpty)
    }

    private static func readyManager() throws -> SessionManager {
        let manager = SessionManager()
        for state in [PayabliTTPSessionState.attestingDevice, .fetchingConfig, .initializingReader(percent: nil), .ready] {
            try manager.advance(to: state)
        }
        return manager
    }
}

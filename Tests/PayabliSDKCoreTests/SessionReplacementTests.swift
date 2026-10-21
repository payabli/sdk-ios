@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// A session whose credential is finished is replaced by the next `initialize`, whatever its configuration, and the
/// state machine is the one place that records it.
final class SessionReplacementTests: XCTestCase {
    override func tearDown() {
        PayabliSession.resetForTesting()
        super.tearDown()
    }

    // MARK: - The machine

    func testTheStateMovesThroughReadyAndReinitializeRequiredAndASuccessorPublishesReadyAgain() {
        let sink = SdkStateSink()
        let first = SessionStateMachine(sink: sink)
        XCTAssertEqual(sink.value, .uninitialized)

        first.markReady()
        XCTAssertEqual(sink.value, .ready)
        first.markReinitializeRequired()
        XCTAssertEqual(sink.value, .reinitializeRequired)
        XCTAssertTrue(first.isFinished)

        SessionStateMachine(sink: sink).markReady()
        XCTAssertEqual(sink.value, .ready)
    }

    func testAFinishedMachineRefusesALaterWriteSoItCannotPublishOverItsSuccessor() {
        let sink = SdkStateSink()
        let replaced = SessionStateMachine(sink: sink)
        replaced.markReady()
        replaced.markReinitializeRequired()
        SessionStateMachine(sink: sink).markReady()

        // A request resuming under the replaced session discovers its finish, or tries to revive it.
        replaced.markReinitializeRequired()
        replaced.markReady()

        XCTAssertEqual(sink.value, .ready)
    }

    func testRetiringAMachinePublishesNothingAndFinishesIt() {
        let sink = SdkStateSink()
        let machine = SessionStateMachine(sink: sink)
        machine.markReady()

        machine.finish()
        machine.markReinitializeRequired()

        XCTAssertTrue(machine.isFinished)
        XCTAssertEqual(sink.value, .ready)
    }

    // MARK: - Replacing a finished session

    func testTheProcessStateReadsUninitializedThenReadyThenReinitializeRequiredThenReadyOnTheSuccessor() async throws {
        let stub = RecordingStub(status: 401)
        stub.install()
        defer { stub.uninstall() }
        XCTAssertEqual(PayabliSession.state, .uninitialized)

        let first = try install(entryPoint: "first")
        XCTAssertEqual(PayabliSession.state, .ready)
        await finishTheCredential(of: first)
        XCTAssertEqual(PayabliSession.state, .reinitializeRequired)

        _ = try install(entryPoint: "second")
        XCTAssertEqual(PayabliSession.state, .ready)
    }

    func testAFinishedSessionIsReplacedByADifferentEntryPoint() async throws {
        let stub = RecordingStub(status: 401)
        stub.install()
        defer { stub.uninstall() }
        let first = try install(entryPoint: "first")
        await finishTheCredential(of: first)

        let second = try install(entryPoint: "second")

        XCTAssertFalse(second === first)
        XCTAssertEqual(second.config.entryPoint, "second")
        XCTAssertTrue(second.isLive)
        XCTAssertFalse(first.isLive, "the replaced session is no longer the installed one")
        XCTAssertTrue(PayabliSession.current === second)
    }

    func testAFinishedSessionIsReplacedByAnEqualConfigurationTooAndItsProviderIsAskedAgain() async throws {
        let stub = RecordingStub(status: 401)
        stub.install()
        defer { stub.uninstall() }
        let calls = Counter()
        let first = try install(entryPoint: "first") { await "token-\(calls.increment())" }
        await finishTheCredential(of: first)
        let before = await calls.count

        let second = try install(entryPoint: "first") { await "token-\(calls.increment())" }
        _ = try? await second.transport.perform(ping())

        XCTAssertFalse(second === first)
        let after = await calls.count
        XCTAssertEqual(after, before + 2, "the fresh session's first read and its refresh, as any session's")
    }

    func testARequestOnAFinishedSessionFailsBeforeItIsSent() async throws {
        let stub = RecordingStub(status: 401)
        stub.install()
        defer { stub.uninstall() }
        let session = try install(entryPoint: "first")
        await finishTheCredential(of: session)
        let sent = stub.count

        let failure = await failure { _ = try await session.transport.perform(self.ping()) }

        XCTAssertEqual((failure as? PayabliGenericError)?.type, .tokenExpired)
        XCTAssertEqual(stub.count, sent)
    }

    func testAUsableSessionStillRefusesADifferentConfigurationAndStaysInstalled() async throws {
        let installed = try install(entryPoint: "first")

        let refused = await failure { _ = try self.install(entryPoint: "second") }

        XCTAssertEqual((refused as? PayabliGenericError)?.type, .invalidConfiguration)
        XCTAssertTrue(PayabliSession.current === installed)
        XCTAssertEqual(PayabliSession.state, .ready)
    }

    func testAUsableSessionIsReturnedForAnEqualConfiguration() throws {
        let installed = try install(entryPoint: "first")

        XCTAssertTrue(try install(entryPoint: "first") === installed)
    }

    func testAStoppedTelemetryClientStartsNoTimerForALaterEvent() async {
        let timerStarted = expectation(description: "the timer started")
        timerStarted.isInverted = true
        let client = TelemetryClient(
            configuration: TelemetryClient.Configuration(entry: "entry", environment: "sandbox"),
            transport: InMemoryTelemetryTransport(),
            sleep: { _ in
                timerStarted.fulfill()
                try await Task.sleep(nanoseconds: .max)
            },
            lifecycle: ManualAppLifecycle(),
            deviceId: { nil },
            queued: []
        )

        await client.stop()
        await client.emit("sdk_initialized")

        await fulfillment(of: [timerStarted], timeout: 0.5)
    }

    // MARK: - Helpers

    private func install(
        entryPoint: String,
        tokenProvider: @escaping PayabliTokenRefresh = { UUID().uuidString }
    ) throws -> PayabliSession {
        try PayabliSession.install(
            config: PayabliConfig(entryPoint: entryPoint, environment: .sandbox, tokenProvider: tokenProvider),
            urlSession: StubURLProtocol.makeSession(),
            telemetryTransport: InMemoryTelemetryTransport()
        )
    }

    /// Finishes the credential the way TRN-05 does: a request refused, and its replay under a fresh token refused too.
    private func finishTheCredential(of session: PayabliSession) async {
        _ = try? await session.transport.perform(ping())
        XCTAssertNotNil(session.auth.terminalFailure, "a refused replay finished the credential")
    }

    private func ping() -> PayabliRequest {
        PayabliRequest(method: .get, path: "/api/v2/ping")
    }

    private func failure(_ block: () async throws -> Void) async -> any Error {
        do {
            try await block()
            XCTFail("expected a failure, got a success")
            return PayabliGenericError(type: .unknown, reason: "no failure")
        } catch {
            return error
        }
    }
}

@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// A request that requires a held credential is sent on the token already held, and never starts a call to the host's
/// token provider. Telemetry's upload is that request.
final class SendsOnHeldCredentialOnlyTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TelemetryRecorders.clear()
    }

    override func tearDown() {
        TelemetryRecorders.clear()
        super.tearDown()
    }

    // MARK: - A session's telemetry

    func testAFlushWithNoTokenMintedCallsNoProviderSendsNothingAndKeepsTheBatch() async throws {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }
        let provider = Counter()
        let session = try makeSession(tokenProvider: {
            _ = await provider.increment()
            return "host-token"
        })
        session.telemetry.record(TelemetryEventName.sdkInitialized)
        let queued = await session.telemetry.bufferedCount

        await session.telemetry.flush()

        let calls = await provider.count
        XCTAssertEqual(calls, 0, "the flush called the host's provider")
        XCTAssertEqual(stub.count, 0, "a batch left with no token held")
        let kept = await session.telemetry.bufferedCount
        XCTAssertEqual(kept, queued, "the batch waits for the next flush")
    }

    func testAFlushAfterHostWorkMintedSendsOnThatTokenAndCallsTheProviderNoMore() async throws {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }
        let provider = Counter()
        let session = try makeSession(tokenProvider: {
            await "host-token-\(provider.increment())"
        })
        _ = try await session.transport.perform(PayabliRequest(method: .get, path: "/api/v2/ping"))
        session.telemetry.record(TelemetryEventName.sdkInitialized)

        await session.telemetry.flush()

        XCTAssertEqual(stub.sentTokens, ["host-token-1", "host-token-1"], "the batch went out on the token host work minted")
        let calls = await provider.count
        XCTAssertEqual(calls, 1, "the flush called the provider")
        let kept = await session.telemetry.bufferedCount
        XCTAssertEqual(kept, 0)
    }

    func testAFlushWhileAMintIsInFlightSendsNothingAndDoesNotJoinIt() async throws {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }
        let entered = Slot<Bool>()
        let release = Latch()
        let session = try makeSession(tokenProvider: {
            entered.set(true)
            await release.wait()
            return "host-token"
        })
        let hostWork = Task { try await session.auth.currentAccessToken() }
        while entered.value == nil {
            await Task.yield()
        }
        session.telemetry.record(TelemetryEventName.sdkInitialized)

        let flushed = Slot<Bool>()
        let flush = Task {
            await session.telemetry.flush()
            flushed.set(true)
        }
        for _ in 0 ..< 300 where flushed.value == nil {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        let returned = flushed.value
        release.open()
        _ = try await hostWork.value
        await flush.value

        XCTAssertEqual(returned, true, "the flush waited on the host's provider call")
        XCTAssertEqual(stub.count, 0, "a batch left while the token was being replaced")
    }

    // MARK: - The transport

    func testARequestWithNothingHeldIsRefusedMissingTokenAndCallsNoProvider() async throws {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }
        let provider = Counter()
        let auth = try makeAuth(provider: provider)
        let transport = makeAuthenticatedStack(auth: auth)

        do {
            _ = try await transport.perform(heldOnly())
            XCTFail("a request requiring a held credential was sent with none held")
        } catch let refusal as PayabliGenericError {
            XCTAssertEqual(refusal.type, .missingToken)
        }

        let calls = await provider.count
        XCTAssertEqual(calls, 0)
        XCTAssertEqual(stub.count, 0)
    }

    func testARequestOnAFinishedSessionIsRefusedMissingTokenAndRecordsNoTokenFailure() async throws {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }
        let recorded = InMemoryTelemetryTransport()
        let channel = makeChannel(transport: recorded)
        TelemetryRecorders.install(channel)
        let provider = Counter()
        let auth = try makeAuth(provider: provider)
        _ = try await auth.currentAccessToken()
        await auth.finish(with: PayabliGenericError(type: .tokenExpired, reason: "Refused"))
        let transport = makeAuthenticatedStack(auth: auth)

        do {
            _ = try await transport.perform(heldOnly())
            XCTFail("a request requiring a held credential was sent on a finished session")
        } catch let refusal as PayabliGenericError {
            XCTAssertEqual(refusal.type, .missingToken)
        }

        await TelemetryRecorders.settled()
        await channel.flush()
        let events = await recorded.drainBatches().flatMap { $0 }
        XCTAssertFalse(events.contains { $0.event == TelemetryEventName.authTokenFailed })
        let calls = await provider.count
        XCTAssertEqual(calls, 1, "the first token only")
        XCTAssertEqual(stub.count, 0)
    }

    func testARequestRefused401IsNotRefreshed() async throws {
        let stub = RecordingStub(status: 401)
        stub.install()
        defer { stub.uninstall() }
        let provider = Counter()
        let auth = try makeAuth(provider: provider)
        _ = try await auth.currentAccessToken()
        let transport = makeAuthenticatedStack(auth: auth)

        let response = try await transport.perform(heldOnly())

        XCTAssertEqual(response.statusCode, 401)
        XCTAssertEqual(stub.count, 1, "no replay")
        let calls = await provider.count
        XCTAssertEqual(calls, 1, "no refresh")
        XCTAssertNil(auth.terminalFailure)
    }

    func testARequestThatDoesNotRequireAHeldCredentialStillMintsOnItsFirstRead() async throws {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }
        let provider = Counter()
        let auth = try makeAuth(provider: provider)
        let transport = makeAuthenticatedStack(auth: auth)

        _ = try await transport.perform(PayabliRequest(method: .post, path: "/api/v2/telemetry/sdk"))

        let calls = await provider.count
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(stub.sentTokens, ["host-token-1"])
    }

    // MARK: - The holder

    func testTheHeldTokenIsAnsweredOnlyWhenNothingReplacesItOrEndsTheSession() async throws {
        let entered = Slot<Bool>()
        let release = Latch()
        let gated = Slot<Bool>()
        let auth = PayabliAuth(config: try PayabliConfig(entryPoint: "entry", environment: .sandbox, tokenProvider: {
            if gated.value == true {
                entered.set(true)
                await release.wait()
                return "rotated"
            }
            return "first"
        }), telemetrySession: .sandbox(entry: "entry"))

        let beforeAnyMint = await auth.heldToken()
        XCTAssertNil(beforeAnyMint)

        _ = try await auth.currentAccessToken()
        let afterTheMint = await auth.heldToken()
        XCTAssertEqual(afterTheMint, "first")

        gated.set(true)
        let rotation = Task { try await auth.invalidateAndRefresh(rejectedToken: "first") }
        while entered.value == nil {
            await Task.yield()
        }
        let duringTheRotation = await auth.heldToken()
        XCTAssertNil(duringTheRotation, "the token being replaced was answered")
        release.open()
        _ = try await rotation.value

        await auth.finish(with: PayabliGenericError(type: .tokenExpired, reason: "Refused"))
        let onceFinished = await auth.heldToken()
        XCTAssertNil(onceFinished)
    }

    // MARK: - The upload

    func testTheUploadRequiresAHeldCredentialAndKeepsTheBatchWhenNoneIsHeld() async {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }
        let service = PayabliService(
            environment: .sandbox,
            readToken: { "minted-token" },
            readHeldToken: { nil },
            client: .none,
            session: StubURLProtocol.makeSession()
        )

        let outcome = await TelemetryEndpointTransport(transport: service).send([event()])

        XCTAssertEqual(outcome, .kept)
        XCTAssertEqual(stub.count, 0, "the upload minted a token to send on")
    }

    // MARK: - Fixtures

    private func heldOnly() -> PayabliRequest {
        PayabliRequest(method: .post, path: "/api/v2/telemetry/sdk", sendsOnHeldCredentialOnly: true)
    }

    private func makeAuth(provider: Counter) throws -> PayabliAuth {
        PayabliAuth(
            config: try PayabliConfig(entryPoint: "entry", environment: .sandbox, tokenProvider: {
                await "host-token-\(provider.increment())"
            }), telemetrySession: .sandbox(entry: "entry"),
            logger: PayabliLogger(category: .auth, sink: RecordingLogSink())
        )
    }

    private func makeSession(tokenProvider: @escaping PayabliTokenRefresh) throws -> PayabliSession {
        let config = try PayabliConfig(entryPoint: "entry", environment: .sandbox, tokenProvider: tokenProvider)
        return PayabliSession(config: config, urlSession: StubURLProtocol.makeSession())
    }

    private func makeChannel(transport: InMemoryTelemetryTransport) -> TelemetryClient {
        TelemetryClient(
            configuration: .init(entry: "entry", environment: "sandbox"),
            transport: transport,
            sleep: ManualTelemetryClock().sleep,
            lifecycle: ManualAppLifecycle(),
            deviceId: { nil },
            queued: []
        )
    }

    private func event() -> TelemetryEvent {
        TelemetryEvent(
            sdkVersion: "0.1.0",
            sessionId: "session-1",
            deviceIdHash: nil,
            entry: "entry",
            environment: "sandbox",
            event: TelemetryEventName.sdkInitialized,
            properties: [:]
        )
    }
}

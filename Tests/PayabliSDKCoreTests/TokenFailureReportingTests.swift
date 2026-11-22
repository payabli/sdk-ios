@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// `auth.tokenFailed` is recorded once per provider call that did not produce a token, by the call that ran it, and
/// waits for its batch.
final class TokenFailureReportingTests: XCTestCase {
    private let transport = InMemoryTelemetryTransport()
    private let clock = ManualTelemetryClock()
    private let lifecycle = ManualAppLifecycle()

    override func setUp() {
        super.setUp()
        TelemetryRecorders.clear()
    }

    override func tearDown() {
        TelemetryRecorders.clear()
        super.tearDown()
    }

    func testAProviderThatThrewReportsThrewAndTheTypeItRaised() async throws {
        let (auth, telemetry) = try makeAuth { throw HostBrokerDown() }

        await assertThrows { _ = try await auth.currentAccessToken() }

        let properties = try await onlyReport(from: telemetry)
        XCTAssertEqual(Set(properties.keys), ["outcome", "reason", "duration_ms", "failure_type"])
        XCTAssertEqual(properties["outcome"], "failed")
        XCTAssertEqual(properties["reason"], "threw")
        XCTAssertEqual(properties["failure_type"], "HostBrokerDown")
        XCTAssertNotNil(Int(properties["duration_ms"] ?? ""))
    }

    func testAProviderThatNeverReturnedReportsTimedOut() async throws {
        let (auth, telemetry) = try makeAuth(clock: FiresOnceRetryClock()) {
            try await Task.sleep(nanoseconds: .max)
            return "never"
        }

        await assertThrows { _ = try await auth.currentAccessToken() }

        let properties = try await onlyReport(from: telemetry)
        XCTAssertEqual(properties["reason"], "timedOut")
        XCTAssertNil(properties["failure_type"])
    }

    func testEachTokenTheHolderRefusesReportsItsOwnReason() async throws {
        for (token, reason) in [("  ", "blankToken"), ("bad\ntoken", "unusableToken")] {
            let (auth, telemetry) = try makeAuth { token }

            await assertThrows { _ = try await auth.currentAccessToken() }

            let properties = try await onlyReport(from: telemetry)
            XCTAssertEqual(properties["reason"], reason, "for \(token.debugDescription)")
            XCTAssertNil(properties["failure_type"])
        }
    }

    func testTheRejectedTokenReturnedAgainReportsUnchangedToken() async throws {
        let (auth, telemetry) = try makeAuth { "same" }
        _ = try await auth.currentAccessToken()

        await assertThrows { _ = try await auth.invalidateAndRefresh(rejectedToken: "same") }

        let properties = try await onlyReport(from: telemetry)
        XCTAssertEqual(properties["reason"], "unchangedToken")
    }

    func testAProviderThatRaisedTheHoldersOwnRefusalReportsReentered() async throws {
        let holder = Slot<PayabliAuth>()
        let (auth, telemetry) = try makeAuth {
            try await XCTUnwrap(holder.value).currentAccessToken()
        }
        holder.set(auth)

        await assertThrows { _ = try await auth.currentAccessToken() }

        let properties = try await onlyReport(from: telemetry)
        XCTAssertEqual(properties["reason"], "reentered")
        XCTAssertNil(properties["failure_type"])
    }

    func testAProviderThatHandledTheRefusalAndFailedOtherwiseReportsThrew() async throws {
        let holder = Slot<PayabliAuth>()
        let (auth, telemetry) = try makeAuth {
            do {
                return try await XCTUnwrap(holder.value).currentAccessToken()
            } catch {
                throw HostBrokerDown()
            }
        }
        holder.set(auth)

        await assertThrows { _ = try await auth.currentAccessToken() }

        let properties = try await onlyReport(from: telemetry)
        XCTAssertEqual(properties["reason"], "threw")
        XCTAssertEqual(properties["failure_type"], "HostBrokerDown")
    }

    func testAProviderThatCopiedEveryFieldOfTheRefusalReportsThrew() async throws {
        let holder = Slot<PayabliAuth>()
        let (auth, telemetry) = try makeAuth {
            do {
                return try await XCTUnwrap(holder.value).currentAccessToken()
            } catch let refusal as PayabliGenericError {
                throw PayabliGenericError(
                    type: refusal.type,
                    reason: refusal.reason,
                    detail: refusal.detail,
                    underlying: refusal.underlying
                )
            }
        }
        holder.set(auth)

        await assertThrows { _ = try await auth.currentAccessToken() }

        let properties = try await onlyReport(from: telemetry)
        XCTAssertEqual(properties["reason"], "threw", "a copy the provider built is the provider's own error")
        XCTAssertEqual(properties["failure_type"], "PayabliGenericError")
    }

    func testAProviderThatRebuiltTheRefusalWithItsOwnReasonReportsThrew() async throws {
        let holder = Slot<PayabliAuth>()
        let (auth, telemetry) = try makeAuth {
            do {
                return try await XCTUnwrap(holder.value).currentAccessToken()
            } catch let refusal as PayabliGenericError {
                throw PayabliGenericError(type: refusal.type, reason: "Host broker unavailable", detail: refusal.detail)
            }
        }
        holder.set(auth)

        await assertThrows { _ = try await auth.currentAccessToken() }

        let properties = try await onlyReport(from: telemetry)
        XCTAssertEqual(properties["reason"], "threw")
        XCTAssertEqual(properties["failure_type"], "PayabliGenericError")
    }

    func testASessionReleasesItsCredentialHolderOnceNothingHoldsIt() throws {
        weak var released: PayabliAuth?
        do {
            let config = try PayabliConfig(entryPoint: "test_entry", environment: .sandbox, tokenProvider: { "token" })
            let session = PayabliSession(config: config, urlSession: StubURLProtocol.makeSession())
            released = session.auth
        }
        XCTAssertNil(released, "the holder outlived its session")
    }

    func testCallersThatJoinedAFailingCallRecordNothingOfTheirOwn() async throws {
        let entered = Slot<Bool>()
        let release = Latch()
        let joined = Latch()
        let joiners = AdmissionCounter(occurrence: 2, admitted: joined)
        let (auth, telemetry) = try makeAuth(onJoinedInFlightMint: { joiners.admit() }) {
            entered.set(true)
            await release.wait()
            throw HostBrokerDown()
        }

        let first = Task { try await auth.currentAccessToken() }
        while entered.value == nil {
            await Task.yield()
        }
        let second = Task { try await auth.currentAccessToken() }
        let third = Task { try await auth.currentAccessToken() }
        await joined.wait()
        release.open()
        for task in [first, second, third] {
            _ = await task.result
        }

        let reports = try await reportsSent(by: telemetry)
        XCTAssertEqual(reports.count, 1, "one provider call failed, so one report")
    }

    func testACallerThatWithdrewWhileTheProviderSucceededRecordsNothing() async throws {
        let entered = Slot<Bool>()
        let release = Latch()
        let (auth, telemetry) = try makeAuth {
            entered.set(true)
            await release.wait()
            return "fresh"
        }

        let waiting = Task { try await auth.currentAccessToken() }
        while entered.value == nil {
            await Task.yield()
        }
        waiting.cancel()
        release.open()
        _ = await waiting.result

        let reports = try await reportsSent(by: telemetry)
        XCTAssertEqual(reports, [])
    }

    func testAReportWaitsForItsBatch() async throws {
        let (auth, telemetry) = try makeAuth { throw HostBrokerDown() }

        await assertThrows { _ = try await auth.currentAccessToken() }
        await TelemetryRecorders.settled()

        let sent = await transport.batches
        XCTAssertTrue(sent.isEmpty, "a send forced by a token failure would go out on the token that failed")
        let buffered = await telemetry.bufferedCount
        XCTAssertEqual(buffered, 1)
    }

    // MARK: - Fixtures

    private struct HostBrokerDown: Error {}

    private func makeAuth(
        clock retryClock: any RetryClock = SystemRetryClock(),
        onJoinedInFlightMint: (@Sendable () -> Void)? = nil,
        provider: @escaping PayabliTokenRefresh
    ) throws -> (PayabliAuth, TelemetryClient) {
        let auth = PayabliAuth(
            config: try PayabliConfig(entryPoint: "test_entry", environment: .sandbox, tokenProvider: provider),
            logger: PayabliLogger(category: .auth),
            clock: retryClock,
            onJoinedInFlightMint: onJoinedInFlightMint
        )
        let telemetry = TelemetryClient(
            configuration: .init(entry: "test_entry", environment: "sandbox"),
            transport: transport,
            sleep: clock.sleep,
            lifecycle: lifecycle,
            deviceId: { nil },
            queued: []
        )
        TelemetryRecorders.install(telemetry)
        return (auth, telemetry)
    }

    private func reportsSent(by telemetry: TelemetryClient) async throws -> [[String: String]] {
        await TelemetryRecorders.settled()
        await telemetry.flush()
        let events = await transport.drainBatches().flatMap { $0 }
        return events.filter { $0.event == TelemetryEventName.authTokenFailed }.map(\.properties)
    }

    private func onlyReport(from telemetry: TelemetryClient) async throws -> [String: String] {
        let reports = try await reportsSent(by: telemetry)
        XCTAssertEqual(reports.count, 1)
        return try XCTUnwrap(reports.first)
    }

    private func assertThrows(_ work: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do {
            try await work()
            XCTFail("expected the call to throw", file: file, line: line)
        } catch {}
    }
}

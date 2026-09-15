import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// The reader reports to the facade, and the facade keeps what it reported.
///
/// A real reader only reports on a device. The provider seam is what makes
/// these answerable on a simulator; what a device still has to answer is that
/// the platform raises the events at all, which is the manual tier.
@MainActor
final class PayabliTTPReaderEventTests: XCTestCase {
    override func setUp() {
        super.setUp()
        StubURLProtocol.handler = Self.configStubHandler
    }

    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    // MARK: - During configuration

    /// The percentage is readable while `prepareReader` is still running, which
    /// is the case a handler installed afterwards would miss.
    func testProgressIsReadableWhileTheReaderConfigures() async throws {
        let (ttp, provider) = try makeTTP()
        var seenDuringPrepare: [Int?] = []
        provider.onPrepare = { seenDuringPrepare.append(ttp.readerConfigurationProgress) }
        provider.readerEventsDuringPrepare = [
            .configurationProgress(percent: 10),
            .configurationProgress(percent: 90)
        ]

        try await ttp.initialize()

        XCTAssertEqual(seenDuringPrepare, [10, 90])
    }

    /// A configuration that ends leaves nothing behind, or a host told to draw
    /// progress while this is not `nil` draws a finished bar for ever.
    func testTheProgressIsClearedWhenTheConfigurationEnds() async throws {
        let (ttp, provider) = try makeTTP()
        provider.readerEventsDuringPrepare = [.configurationProgress(percent: 100)]

        try await ttp.initialize()

        XCTAssertEqual(ttp.sessionState, .ready)
        XCTAssertNil(ttp.readerConfigurationProgress)
    }

    /// A configuration that fails leaves nothing behind either.
    func testTheProgressIsClearedWhenTheConfigurationFails() async throws {
        let (ttp, provider) = try makeTTP()
        provider.readerEventsDuringPrepare = [.configurationProgress(percent: 40)]
        provider.prepareReaderResult = .failure(PayabliTTPError.readerSetupFailed(reason: "no reader"))

        _ = try? await ttp.initialize()

        XCTAssertNil(ttp.readerConfigurationProgress)
    }

    func testNothingIsKeptUntilTheReaderReports() async throws {
        let (ttp, _) = try makeTTP()

        try await ttp.initialize()

        XCTAssertNil(ttp.readerConfigurationProgress)
    }

    // MARK: - After the session is up

    /// The subscription lives for the session, so the seam still delivers after
    /// `initialize()` has returned.
    func testTheSeamStillDeliversAfterTheSessionIsUp() async throws {
        let (ttp, provider) = try makeTTP()
        try await ttp.initialize()

        provider.emitReaderEvent(.configurationProgress(percent: 55))
        await Task.yield()

        XCTAssertEqual(ttp.readerConfigurationProgress, 55)
    }

    /// A card-read state is not progress, and must not be read as any.
    func testACardStateLeavesTheProgressAlone() async throws {
        let (ttp, provider) = try makeTTP()
        try await ttp.initialize()
        provider.emitReaderEvent(.configurationProgress(percent: 70))
        await Task.yield()

        provider.emitReaderEvent(.cardDetected)
        provider.emitReaderEvent(.cardRemovalRequested)
        await Task.yield()

        XCTAssertEqual(ttp.readerConfigurationProgress, 70)
    }

    /// The provider contract ends callbacks at `cleanUp()`, so a reader that
    /// reports afterwards is a stale subscription rather than a late event.
    func testNothingIsKeptFromAReaderThatHasBeenCleanedUp() async throws {
        let (ttp, provider) = try makeTTP()
        try await ttp.initialize()
        provider.emitReaderEvent(.configurationProgress(percent: 40))
        await Task.yield()
        XCTAssertEqual(ttp.readerConfigurationProgress, 40)

        await provider.cleanUp()
        provider.emitReaderEvent(.configurationProgress(percent: 90))
        await Task.yield()

        XCTAssertEqual(ttp.readerConfigurationProgress, 40, "an event arrived after cleanUp")
    }

    // MARK: - Announced to a host

    /// A subscriber is told progress moved, and the payload carries where it
    /// got to for a bridge host that has no property to read.
    func testProgressIsAnnouncedWithItsPercentage() async throws {
        let (ttp, provider) = try makeTTP()
        try await ttp.initialize()

        let collector = collectFirst(from: ttp.events()) { event -> Int? in
            guard case let .readerConfigurationProgressChanged(percent) = event else { return nil }
            return percent
        }
        provider.emitReaderEvent(.configurationProgress(percent: 73))

        let percent = try await firstValue(of: collector, named: "readerConfigurationProgressChanged")
        XCTAssertEqual(percent, 73)
    }

    /// The property is written before the announcement, so a subscriber reading
    /// it on being told it moved does not read the previous value.
    func testTheProgressIsReadableWhenTheAnnouncementArrives() async throws {
        let (ttp, provider) = try makeTTP()
        try await ttp.initialize()

        let collector = collectFirst(from: ttp.events()) { event -> Int? in
            guard case let .readerConfigurationProgressChanged(percent) = event else { return nil }
            return percent
        }
        provider.emitReaderEvent(.configurationProgress(percent: 61))

        _ = try await firstValue(of: collector, named: "readerConfigurationProgressChanged")
        XCTAssertEqual(
            ttp.readerConfigurationProgress, 61,
            "the announcement arrived before the value it is about was readable"
        )
    }

    /// Every card state a host acts on reaches it, in the order the reader
    /// raised them.
    func testTheCardStatesReachAHostInOrder() async throws {
        let (ttp, provider) = try makeTTP()
        try await ttp.initialize()

        let wanted: [PayabliTTPEventCode] = [
            .cardDetected, .pinEntryRequested, .pinEntryCompleted,
            .cardRemovalRequested, .cardReadRetryRequested,
            .readerNotReady, .readerPromptDismissed
        ]
        // Subscribed before anything is raised: a stream taken inside the task
        // would not exist yet when the events below are emitted.
        let stream = ttp.events()
        let collector = Task { () -> [PayabliTTPEventCode] in
            var seen: [PayabliTTPEventCode] = []
            for await event in stream {
                seen.append(event.code)
                if seen.count == wanted.count {
                    return seen
                }
            }
            return seen
        }

        for event in [
            TapToPayReaderEvent.cardDetected, .pinEntryRequested, .pinEntryCompleted,
            .cardRemovalRequested, .cardReadRetryRequested, .notReady, .promptDismissed
        ] {
            provider.emitReaderEvent(event)
        }

        let deadline = Task {
            guard (try? await Task.sleep(nanoseconds: Self.eventWait)) != nil else { return }
            collector.cancel()
        }
        let seen = await collector.value
        deadline.cancel()
        XCTAssertEqual(seen, wanted)
    }

    // MARK: - Fixtures

    /// How long an event has to arrive before the test says it never did.
    private static let eventWait: UInt64 = 2_000_000_000

    /// Reads the stream for the first event `match` accepts. Bounded by
    /// `firstValue`, so a missing event fails a test rather than hanging it.
    private func collectFirst<T: Sendable>(
        from stream: AsyncStream<PayabliTTPEvent>,
        match: @escaping @Sendable (PayabliTTPEvent) -> T?
    ) -> Task<T?, Never> {
        Task {
            for await event in stream {
                if let found = match(event) {
                    return found
                }
            }
            return nil
        }
    }

    private func firstValue<T: Sendable>(of collector: Task<T?, Never>, named name: String) async throws -> T {
        let deadline = Task {
            // A cancelled sleep throws, and swallowing that would cancel the
            // collector after it had already answered.
            guard (try? await Task.sleep(nanoseconds: Self.eventWait)) != nil else { return }
            collector.cancel()
        }
        let found = await collector.value
        deadline.cancel()
        return try XCTUnwrap(found, "no \(name) event arrived")
    }

    private func makeTTP() throws -> (PayabliTTP, MockTapToPayProvider) {
        let provider = MockTapToPayProvider()
        let ttp = PayabliTTP(
            config: try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" }),
            appId: "appid",
            provider: provider,
            attestation: MockDeviceAttestationService(),
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )
        return (ttp, provider)
    }

    private static let configStubHandler: StubURLProtocol.Handler = { request in
        let body: [String: Any] = [
            "responseCode": 1,
            "isSuccess": true,
            "responseData": [
                "credentials": [
                    "secretKey": "s",
                    "apiKey": "a",
                    "merchantId": "m",
                    "terminalId": "t"
                ]
            ],
            "paymentToken": "payment_tok"
        ]
        let data = try JSONSerialization.data(withJSONObject: body)
        return (HTTPURLResponse(
            url: request.url!,
            statusCode: 200,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!, data)
    }
}

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

    /// Every percentage the configuration raises is announced, in order.
    func testEveryPercentageIsAnnouncedInOrder() async throws {
        let (ttp, provider) = try makeTTP()
        let stream = ttp.events()
        let collector = Task { () -> [Int] in
            var seen: [Int] = []
            for await event in stream {
                if case let .readerConfigurationProgressChanged(percent) = event {
                    seen.append(percent)
                }
                if case .readerReady = event {
                    return seen
                }
            }
            return seen
        }
        provider.readerEventsDuringPrepare = [
            .configurationProgress(percent: 10),
            .configurationProgress(percent: 90)
        ]

        try await ttp.initialize()

        let announced = await collector.value
        XCTAssertEqual(announced, [10, 90])
    }

    // MARK: - After the session is up

    /// The subscription lives for the session, so card states still reach a host
    /// after `initialize()` has returned.
    func testCardStatesStillReachAHostAfterTheSessionIsUp() async throws {
        let (ttp, provider) = try makeTTP()
        try await ttp.initialize()

        let stream = ttp.events()
        let collector = collectFirst(from: stream) { event -> PayabliTTPEventCode? in
            guard case .cardDetected = event else { return nil }
            return event.code
        }
        provider.emitReaderEvent(.cardDetected)

        let code = try await firstValue(of: collector, named: "cardDetected")
        XCTAssertEqual(code, .cardDetected)
    }

    /// Progress belongs to one configuration, so a percentage raised once that
    /// configuration has ended is dropped rather than published. Publishing it
    /// would leave a value nothing clears and a bar a host cannot dismiss.
    func testProgressFromAnEndedConfigurationIsDropped() async throws {
        let (ttp, provider) = try makeTTP()
        try await ttp.initialize()

        let stream = ttp.events()
        let announced = Task { () -> Bool in
            for await event in stream {
                if case .readerConfigurationProgressChanged = event {
                    return true
                }
                if case .cardDetected = event {
                    return false
                }
            }
            return false
        }

        provider.emitReaderEvent(.configurationProgress(percent: 90))
        // A card state behind it, so the collector answers rather than waiting
        // for an event that is never coming.
        provider.emitReaderEvent(.cardDetected)

        let wasAnnounced = await announced.value
        XCTAssertFalse(wasAnnounced, "a configuration that has ended announced progress")
    }

    /// A card-read state is not progress, and is never announced as any.
    func testACardStateIsNeverAnnouncedAsProgress() async throws {
        let (ttp, provider) = try makeTTP()
        let stream = ttp.events()
        let collector = Task { () -> Bool in
            for await event in stream {
                if case .readerConfigurationProgressChanged = event {
                    return true
                }
                if case .readerReady = event {
                    return false
                }
            }
            return false
        }
        provider.readerEventsDuringPrepare = [.cardDetected, .cardRemovalRequested]

        try await ttp.initialize()

        let sawProgress = await collector.value
        XCTAssertFalse(sawProgress)
    }

    // MARK: - Announced to a host

    /// A subscriber is told progress moved, and the payload carries where it
    /// got to for a bridge host that has no property to read.
    func testProgressIsAnnouncedWithItsPercentage() async throws {
        let (ttp, provider) = try makeTTP()
        let collector = collectFirst(from: ttp.events()) { event -> Int? in
            guard case let .readerConfigurationProgressChanged(percent) = event else { return nil }
            return percent
        }
        provider.readerEventsDuringPrepare = [.configurationProgress(percent: 73)]

        try await ttp.initialize()

        let percent = try await firstValue(of: collector, named: "readerConfigurationProgressChanged")
        XCTAssertEqual(percent, 73)
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

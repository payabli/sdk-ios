import Combine
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

    /// Every percentage reaches the state the configuration is in, so a host
    /// reading `sessionState` sees how far the reader has got.
    func testEveryPercentageReachesTheStateInOrder() async throws {
        let (ttp, provider) = try makeTTP()
        var seen: [Int?] = []
        provider.readerEventsDuringPrepare = [
            .configurationProgress(percent: 10),
            .configurationProgress(percent: 90)
        ]
        let watcher = ttp.$sessionState.sink { state in
            if case let .initializingReader(percent) = state, percent != nil {
                seen.append(percent)
            }
        }
        defer { watcher.cancel() }

        try await ttp.initialize()

        XCTAssertEqual(seen, [10, 90])
    }

    /// A configuration that ends takes its percentage with it, because the
    /// percentage is part of the state rather than a value beside it.
    func testTheStateThatEndsTakesThePercentageWithIt() async throws {
        let (ttp, provider) = try makeTTP()
        provider.readerEventsDuringPrepare = [.configurationProgress(percent: 100)]

        try await ttp.initialize()

        XCTAssertEqual(ttp.sessionState, .ready)
        XCTAssertNil(ttp.sessionState.readerConfigurationPercent)
    }

    /// Progress raised once its configuration has ended reaches nothing: the
    /// state has moved on and the percentage has nowhere to land.
    func testProgressFromAnEndedConfigurationIsDropped() async throws {
        let (ttp, provider) = try makeTTP()
        try await ttp.initialize()

        provider.emitReaderEvent(.configurationProgress(percent: 90))
        await Task.yield()

        XCTAssertEqual(ttp.sessionState, .ready)
        XCTAssertNil(ttp.sessionState.readerConfigurationPercent)
    }

    /// A card-read state is not progress, and never lands as any.
    func testACardStateIsNeverRecordedAsProgress() async throws {
        let (ttp, provider) = try makeTTP()
        provider.readerEventsDuringPrepare = [.cardDetected, .cardRemovalRequested]

        try await ttp.initialize()

        XCTAssertNil(ttp.sessionState.readerConfigurationPercent)
    }

    /// A card state raised while no charge holds the reader leaves the session where it was.
    func testACardStateOutsideAChargeLeavesTheSessionReady() async throws {
        let (ttp, provider) = try makeTTP()
        try await ttp.initialize()

        for event in [
            TapToPayReaderEvent.cardDetected, .pinEntryRequested, .pinEntryCompleted,
            .cardRemovalRequested, .cardReadRetryRequested, .notReady, .promptDismissed
        ] {
            provider.emitReaderEvent(event)
        }

        XCTAssertEqual(ttp.sessionState, .ready)
        XCTAssertTrue(ttp.isReady)
    }

    // MARK: - Fixtures

    private func makeTTP() throws -> (PayabliTTP, MockTapToPayProvider) {
        let provider = MockTapToPayProvider()
        let ttp = PayabliTTP(
            config: try PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" }),
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

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

    /// The percentage arrives while `prepareReader` is still running, which is
    /// the case a handler installed afterwards would miss.
    func testProgressRaisedWhileTheReaderConfiguresIsKept() async throws {
        let (ttp, provider) = try makeTTP()
        provider.readerEventsDuringPrepare = [
            .configurationProgress(percent: 10),
            .configurationProgress(percent: 90)
        ]

        try await ttp.initialize()

        XCTAssertEqual(ttp.readerConfigurationProgress, 90)
    }

    func testNothingIsKeptUntilTheReaderReports() async throws {
        let (ttp, _) = try makeTTP()

        try await ttp.initialize()

        XCTAssertNil(ttp.readerConfigurationProgress)
    }

    // MARK: - After the session is up

    /// The subscription lives for the session, so a later configuration
    /// reports through the same seam.
    func testProgressRaisedAfterTheSessionIsUpIsKept() async throws {
        let (ttp, provider) = try makeTTP()
        try await ttp.initialize()

        provider.emitReaderEvent(.configurationProgress(percent: 55))
        await Task.yield()

        XCTAssertEqual(ttp.readerConfigurationProgress, 55)
    }

    /// A card-read state is not progress, and must not be read as any.
    func testACardStateLeavesTheProgressAlone() async throws {
        let (ttp, provider) = try makeTTP()
        provider.readerEventsDuringPrepare = [.configurationProgress(percent: 100)]
        try await ttp.initialize()

        provider.emitReaderEvent(.cardDetected)
        provider.emitReaderEvent(.cardRemovalRequested)
        await Task.yield()

        XCTAssertEqual(ttp.readerConfigurationProgress, 100)
    }

    // MARK: - Fixtures

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

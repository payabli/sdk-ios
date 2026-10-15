@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// A paypoint whose gateway keys come back blank, from the configuration route to what the host is told and
/// where the session is left.
@MainActor
final class PayabliTTPReaderCredentialsTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    func testBlankGatewayKeysReachTheHostAs3010AndLandAsARejectedConfiguration() async throws {
        StubURLProtocol.handler = TapToPayReportsTests.configHandler(
            status: 200,
            credentials: ["secretKey": "", "apiKey": "", "merchantId": "m", "terminalId": "t"]
        )
        let attestation = MockDeviceAttestationService()
        attestation.isAlreadyAttested = true
        let ttp = try PayabliTTP(
            config: PayabliConfig(entryPoint: "e", environment: .sandbox, tokenProvider: { "seed_token" }),
            provider: ReaderCheckingProvider(),
            attestation: attestation,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            session: StubURLProtocol.makeSession()
        )

        do {
            try await ttp.initialize()
            XCTFail("expected blank keys to be refused")
        } catch let error as TapToPayError {
            XCTAssertEqual(error.code, 3010)
            XCTAssertEqual(error.type, .readerCredentialsUnusable)
            XCTAssertEqual(error.reason, "The card reader's configuration is incomplete.")
            XCTAssertNil(error.detail)
            for key in ["secretKey", "apiKey"] {
                XCTAssertFalse(error.localizedDescription.contains(key), error.localizedDescription)
            }
        }
        XCTAssertEqual(ttp.sessionState, .failed(reason: .configurationRejected))
    }
}

/// Everything succeeds except `configure`, which is the real reader's check of the credentials.
private final class ReaderCheckingProvider: TapToPayProvider, @unchecked Sendable {
    static var providerId: String {
        "reader-checking"
    }

    private let reader = FiservCardReader()

    func checkEligibility() async -> Result<Void, PayabliTTPError> {
        .success(())
    }

    func configure(credentials: [String: String]) throws {
        try reader.configure(credentials: credentials)
    }

    func prepareReader(onReaderEvent _: @escaping @MainActor @Sendable (TapToPayReaderEvent) -> Void) async throws {}

    func areTermsAccepted() async throws -> Bool {
        true
    }

    func presentTerms() async throws {}

    func startReading(_: CardReadRequest) async throws -> CardReadResult {
        throw PayabliTTPError.readerSetupFailed(reason: "not used")
    }

    func cancelReading() async {}

    func cleanUp() async {}
}

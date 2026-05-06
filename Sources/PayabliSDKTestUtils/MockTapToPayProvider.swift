import Foundation
import PayabliSDKTapToPay

/// Mock `TapToPayProvider` for unit tests that exercise the TTP session and
/// charge flows without requiring a physical NFC reader.
public final class MockTapToPayProvider: TapToPayProvider, @unchecked Sendable {
    public static var providerId: String { "mock" }

    public var eligibility: Result<Void, PayabliTTPError> = .success(())
    public var prepareReaderResult: Result<Void, Error> = .success(())
    public var readingResult: Result<CardReadResult, Error> = .success(
        CardReadResult(
            provider: "mock",
            encryptedPayload: Data("encrypted".utf8),
            cardNetwork: "Visa",
            providerMetadata: ["last4": "1111"]
        )
    )

    public var prepareReaderCalls = 0
    public var configureCalls = 0
    public var startReadingCalls = 0
    public var cancelCalls = 0
    public var cleanUpCalls = 0
    public var lastConfiguredCredentials: [String: String]?
    public var configureResult: Result<Void, Error> = .success(())

    public init() {}

    public func checkEligibility() async -> Result<Void, PayabliTTPError> { eligibility }

    public func configure(credentials: [String: String]) throws {
        configureCalls += 1
        lastConfiguredCredentials = credentials
        if case .failure(let err) = configureResult { throw err }
    }

    public func prepareReader() async throws {
        prepareReaderCalls += 1
        if case .failure(let err) = prepareReaderResult { throw err }
    }

    public func startReading(_ request: CardReadRequest) async throws -> CardReadResult {
        startReadingCalls += 1
        switch readingResult {
        case .success(let result): return result
        case .failure(let err): throw err
        }
    }

    public func cancelReading() async { cancelCalls += 1 }
    public func cleanUp() async { cleanUpCalls += 1 }
}

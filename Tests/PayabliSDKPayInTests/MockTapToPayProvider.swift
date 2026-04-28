import Foundation
@testable import PayabliSDKPayIn

final class MockTapToPayProvider: TapToPayProvider, @unchecked Sendable {
    static var providerId: String { "mock" }

    var eligibility: Result<Void, PayabliTTPError> = .success(())
    var prepareReaderResult: Result<Void, Error> = .success(())
    var readingResult: Result<CardReadResult, Error> = .success(
        CardReadResult(
            provider: "mock",
            encryptedPayload: Data("encrypted".utf8),
            cardNetwork: "Visa",
            providerMetadata: ["last4": "1111"]
        )
    )

    var prepareReaderCalls = 0
    var configureCalls = 0
    var startReadingCalls = 0
    var cancelCalls = 0
    var cleanUpCalls = 0
    var lastConfiguredCredentials: [String: String]?
    var configureResult: Result<Void, Error> = .success(())

    func checkEligibility() async -> Result<Void, PayabliTTPError> { eligibility }

    func configure(credentials: [String: String]) throws {
        configureCalls += 1
        lastConfiguredCredentials = credentials
        if case .failure(let err) = configureResult { throw err }
    }

    func prepareReader() async throws {
        prepareReaderCalls += 1
        if case .failure(let err) = prepareReaderResult { throw err }
    }

    func startReading(_ request: CardReadRequest) async throws -> CardReadResult {
        startReadingCalls += 1
        switch readingResult {
        case .success(let result): return result
        case .failure(let err): throw err
        }
    }

    func cancelReading() async { cancelCalls += 1 }
    func cleanUp() async { cleanUpCalls += 1 }
}

final class MockDeviceAttestationService: DeviceAttestationService, @unchecked Sendable {
    var isAlreadyAttested: Bool = false
    var cachedDeviceId: String?
    var attestResult: Result<AttestationResult, Error> = .success(
        AttestationResult(keyId: "mock_key", deviceId: "mock_device")
    )
    var activationResult: Result<Void, Error> = .success(())
    var attestCalls = 0
    var assertionCalls = 0
    var activateCalls = 0

    func attest(entry: String, appId: String) async throws -> AttestationResult {
        attestCalls += 1
        switch attestResult {
        case .success(let result):
            isAlreadyAttested = true
            cachedDeviceId = result.deviceId
            return result
        case .failure(let err): throw err
        }
    }

    func generateAssertion() async throws -> AssertionHeaders {
        assertionCalls += 1
        return AssertionHeaders(
            assertion: "mock_assertion",
            keyId: "mock_key",
            deviceId: "mock_device",
            timestamp: "2026-04-21T00:00:00Z"
        )
    }

    func activateDevice(activationCode: String, entry: String) async throws {
        activateCalls += 1
        if case .failure(let err) = activationResult { throw err }
    }

    func clearCache() {
        isAlreadyAttested = false
    }
}

import Foundation
@testable import PayabliSDKTapToPay

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

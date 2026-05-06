import Foundation
import PayabliSDKTapToPay

/// Mock `DeviceAttestationService` for unit tests that exercise the TTP
/// initialization and activation flows without requiring App Attest entitlements
/// or network access.
public final class MockDeviceAttestationService: DeviceAttestationService, @unchecked Sendable {
    public var isAlreadyAttested: Bool = false
    public var cachedDeviceId: String?
    public var attestResult: Result<AttestationResult, Error> = .success(
        AttestationResult(keyId: "mock_key", deviceId: "mock_device")
    )
    public var activationResult: Result<Void, Error> = .success(())
    public var attestCalls = 0
    public var assertionCalls = 0
    public var activateCalls = 0

    public init() {}

    public func attest(entry: String, appId: String) async throws -> AttestationResult {
        attestCalls += 1
        switch attestResult {
        case .success(let result):
            isAlreadyAttested = true
            cachedDeviceId = result.deviceId
            return result
        case .failure(let err): throw err
        }
    }

    public func generateAssertion() async throws -> AssertionHeaders {
        assertionCalls += 1
        return AssertionHeaders(
            assertion: "mock_assertion",
            keyId: "mock_key",
            deviceId: "mock_device",
            timestamp: "2026-04-21T00:00:00Z"
        )
    }

    public func activateDevice(activationCode: String, entry: String) async throws {
        activateCalls += 1
        if case .failure(let err) = activationResult { throw err }
    }

    public func clearCache() {
        isAlreadyAttested = false
    }
}

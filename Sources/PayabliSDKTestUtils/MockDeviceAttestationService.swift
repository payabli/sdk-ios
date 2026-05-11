import Foundation
import PayabliSDKTapToPay

/// Mock `DeviceAttestationService` for unit tests that exercise the TTP
/// initialization and activation flows without requiring App Attest entitlements
/// or network access.
public final class MockDeviceAttestationService: DeviceAttestationService, @unchecked Sendable {
    private let lock = NSLock()

    private var _isAlreadyAttested = false
    public var isAlreadyAttested: Bool {
        get { lock.withLock { _isAlreadyAttested } }
        set { lock.withLock { _isAlreadyAttested = newValue } }
    }

    private var _cachedDeviceId: String?
    public var cachedDeviceId: String? {
        get { lock.withLock { _cachedDeviceId } }
        set { lock.withLock { _cachedDeviceId = newValue } }
    }

    private var _attestResult: Result<AttestationResult, Error> = .success(
        AttestationResult(keyId: "mock_key", deviceId: "mock_device")
    )
    public var attestResult: Result<AttestationResult, Error> {
        get { lock.withLock { _attestResult } }
        set { lock.withLock { _attestResult = newValue } }
    }

    private var _activationResult: Result<Void, Error> = .success(())
    public var activationResult: Result<Void, Error> {
        get { lock.withLock { _activationResult } }
        set { lock.withLock { _activationResult = newValue } }
    }

    private var _attestCalls = 0
    public var attestCalls: Int {
        lock.withLock { _attestCalls }
    }

    private var _assertionCalls = 0
    public var assertionCalls: Int {
        lock.withLock { _assertionCalls }
    }

    private var _activateCalls = 0
    public var activateCalls: Int {
        lock.withLock { _activateCalls }
    }

    public init() {}

    public func attest(entry: String, appId: String) async throws -> AttestationResult {
        let result: Result<AttestationResult, Error> = lock.withLock {
            _attestCalls += 1
            return _attestResult
        }
        switch result {
        case .success(let value):
            lock.withLock {
                _isAlreadyAttested = true
                _cachedDeviceId = value.deviceId
            }
            return value
        case .failure(let err):
            throw err
        }
    }

    public func generateAssertion() async throws -> AssertionHeaders {
        lock.withLock { _assertionCalls += 1 }
        return AssertionHeaders(
            assertion: "mock_assertion",
            keyId: "mock_key",
            deviceId: "mock_device",
            timestamp: "2026-04-21T00:00:00Z"
        )
    }

    public func activateDevice(activationCode: String, entry: String) async throws {
        let result: Result<Void, Error> = lock.withLock {
            _activateCalls += 1
            return _activationResult
        }
        if case .failure(let err) = result { throw err }
    }

    public func clearCache() {
        lock.withLock { _isAlreadyAttested = false }
    }
}

import Foundation
import PayabliSDKTapToPay

/// Mock `DeviceAttestationService` for unit tests that exercise the TTP
/// initialization and activation flows without requiring App Attest entitlements
/// or network access.
public final class MockDeviceAttestationService: DeviceAttestationService, @unchecked Sendable {
    private let lock = NSLock()

    /// Which entry points hold a binding, and the handle each was registered
    /// under. Keyed, so a test can set one entry point up and check that another
    /// reads as unenrolled.
    private var _bindings: [String: String] = [:]
    public var bindings: [String: String] {
        get { lock.withLock { _bindings } }
        set { lock.withLock { _bindings = newValue } }
    }

    /// Sets or clears the binding every entry point sees. For tests that only
    /// care whether the device is enrolled, not for which paypoint.
    public var isAlreadyAttested: Bool {
        get { lock.withLock { !_bindings.isEmpty } }
        set { lock.withLock { _bindings = newValue ? [Self.anyEntry: "mock_device"] : [:] } }
    }

    /// The handle any entry point would read, when only one was set up.
    public var cachedDeviceId: String? {
        get { lock.withLock { _bindings.values.first } }
        set { lock.withLock { _bindings = newValue.map { [Self.anyEntry: $0] } ?? [:] } }
    }

    /// The entry point the unkeyed setters above stand in for.
    public static let anyEntry = "mockEntry"

    public func isAttested(for entry: String) -> Bool {
        lock.withLock { _bindings[entry] != nil || _bindings[Self.anyEntry] != nil }
    }

    public func cachedDeviceId(for entry: String) -> String? {
        lock.withLock { _bindings[entry] ?? _bindings[Self.anyEntry] }
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
        case let .success(value):
            lock.withLock { _bindings[entry] = value.deviceId }
            return value
        case let .failure(err):
            throw err
        }
    }

    public func generateAssertion(for entry: String) async throws -> AssertionHeaders {
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
        if case let .failure(err) = result {
            throw err
        }
    }

    public func clearCache(for entry: String) {
        lock.withLock {
            _bindings[entry] = nil
            _bindings[Self.anyEntry] = nil
        }
    }
}

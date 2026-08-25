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
    private var storedBindings: [String: String] = [:]
    public var bindings: [String: String] {
        get { lock.withLock { storedBindings } }
        set { lock.withLock { storedBindings = newValue } }
    }

    /// Sets or clears the binding every entry point sees. For tests that only
    /// care whether the device is enrolled, not for which paypoint.
    public var isAlreadyAttested: Bool {
        get { lock.withLock { !storedBindings.isEmpty } }
        set { lock.withLock { storedBindings = newValue ? [Self.anyEntry: "mock_device"] : [:] } }
    }

    /// The handle any entry point would read, when only one was set up.
    public var cachedDeviceId: String? {
        get { lock.withLock { storedBindings.values.first } }
        set { lock.withLock { storedBindings = newValue.map { [Self.anyEntry: $0] } ?? [:] } }
    }

    /// The entry point the unkeyed setters above stand in for.
    public static let anyEntry = "mockEntry"

    /// The key each entry point's binding names, for the drop that compares both.
    /// An entry point with none set answers `defaultKeyId`, which is what
    /// `generateAssertion` hands out, so a test that never mentions a key sees a
    /// binding and an assertion that agree.
    private var storedKeys: [String: String] = [:]
    public var bindingKeys: [String: String] {
        get { lock.withLock { storedKeys } }
        set { lock.withLock { storedKeys = newValue } }
    }

    /// What `generateAssertion` signs with, and what a binding names when a test
    /// sets no key of its own.
    public static let defaultKeyId = "mock_key"

    /// Raised by the two reads below while it is set, so a test can drive the
    /// warm path failing before the cold sequence is ever reached.
    public var readFailure: Error? {
        get { lock.withLock { storedReadFailure } }
        set { lock.withLock { storedReadFailure = newValue } }
    }

    private var storedReadFailure: Error?

    public func isAttested(for entry: String) async throws -> Bool {
        try lock.withLock {
            if let storedReadFailure {
                throw storedReadFailure
            }
            return storedBindings[entry] != nil || storedBindings[Self.anyEntry] != nil
        }
    }

    public func cachedDeviceId(for entry: String) throws -> String? {
        try lock.withLock {
            if let storedReadFailure {
                throw storedReadFailure
            }
            return storedBindings[entry] ?? storedBindings[Self.anyEntry]
        }
    }

    private var storedAttestResult: Result<AttestationResult, Error> = .success(
        AttestationResult(keyId: "mock_key", deviceId: "mock_device")
    )
    public var attestResult: Result<AttestationResult, Error> {
        get { lock.withLock { storedAttestResult } }
        set { lock.withLock { storedAttestResult = newValue } }
    }

    private var storedActivationResult: Result<Void, Error> = .success(())
    public var activationResult: Result<Void, Error> {
        get { lock.withLock { storedActivationResult } }
        set { lock.withLock { storedActivationResult = newValue } }
    }

    private var storedAttestCalls = 0
    public var attestCalls: Int {
        lock.withLock { storedAttestCalls }
    }

    private var storedAssertionCalls = 0
    public var assertionCalls: Int {
        lock.withLock { storedAssertionCalls }
    }

    private var storedActivateCalls = 0
    public var activateCalls: Int {
        lock.withLock { storedActivateCalls }
    }

    public init() {}

    public func attest(entry: String, appId: String) async throws -> AttestationResult {
        let result: Result<AttestationResult, Error> = lock.withLock {
            storedAttestCalls += 1
            return storedAttestResult
        }
        switch result {
        case let .success(value):
            lock.withLock { storedBindings[entry] = value.deviceId }
            return value
        case let .failure(err):
            throw err
        }
    }

    /// Refuses a paypoint with no binding, as the real service does. Succeeding
    /// regardless let a test pass where production throws.
    public func generateAssertion(for entry: String) async throws -> AssertionHeaders {
        let held: (deviceId: String, keyId: String)? = lock.withLock {
            storedAssertionCalls += 1
            let key = storedBindings[entry] != nil ? entry : Self.anyEntry
            guard let deviceId = storedBindings[key] else { return nil }
            return (deviceId, storedKeys[key] ?? Self.defaultKeyId)
        }
        guard let held else {
            throw PayabliTTPError.attestationFailed(reason: "Missing attestation state")
        }
        let (deviceId, keyId) = held
        return AssertionHeaders(
            assertion: "mock_assertion",
            keyId: keyId,
            deviceId: deviceId,
            timestamp: "2026-04-21T00:00:00Z"
        )
    }

    public func activateDevice(activationCode: String, entry: String) async throws {
        let result: Result<Void, Error> = lock.withLock {
            storedActivateCalls += 1
            return storedActivationResult
        }
        if case let .failure(err) = result {
            throw err
        }
    }

    /// Raised by `clearCache` while it is set, so a test can drive a caller whose
    /// correctness rests on the drop having happened.
    public var clearFailure: Error? {
        get { lock.withLock { storedClearFailure } }
        set { lock.withLock { storedClearFailure = newValue } }
    }

    private var storedClearFailure: Error?

    public func clearCache(for entry: String) throws {
        try lock.withLock {
            if let storedClearFailure {
                throw storedClearFailure
            }
            storedBindings[entry] = nil
            storedBindings[Self.anyEntry] = nil
            storedKeys[entry] = nil
            storedKeys[Self.anyEntry] = nil
        }
    }

    /// Compares and removes under the one lock the bindings are read through, so a
    /// test can replace a binding mid-request and the drop still sees one of the
    /// two values rather than a torn state.
    ///
    /// The key is compared alongside the handle, as `AppAttestService` does: a
    /// binding that kept its handle across a key rotation is not the one a refusal
    /// was about, and a double that dropped it anyway would pass a facade test for
    /// behaviour production does not have.
    @discardableResult
    public func forgetRefusedBinding(entry: String, deviceId: String, keyId: String) throws -> Bool {
        try lock.withLock {
            if let storedClearFailure {
                throw storedClearFailure
            }
            let key = storedBindings[entry] != nil ? entry : Self.anyEntry
            guard storedBindings[key] == deviceId,
                  storedKeys[key] ?? Self.defaultKeyId == keyId
            else {
                return false
            }
            storedBindings[key] = nil
            storedKeys[key] = nil
            return true
        }
    }
}

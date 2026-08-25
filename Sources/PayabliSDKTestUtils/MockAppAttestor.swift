import Foundation
import PayabliSDKTapToPay

/// Mock `AppAttestor` for unit tests that exercise attestation flows without
/// hitting `DCAppAttestService`.
public final class MockAppAttestor: AppAttestor, @unchecked Sendable {
    private let lock = NSLock()

    private var _isSupported = true
    public var isSupported: Bool {
        get { lock.withLock { _isSupported } }
        set { lock.withLock { _isSupported = newValue } }
    }

    private var _generatedKeyId = AppAttestKeyId("mock_keyId")
    public var generatedKeyId: AppAttestKeyId {
        get { lock.withLock { _generatedKeyId } }
        set { lock.withLock { _generatedKeyId = newValue } }
    }

    private var _attestationPayload = AttestationObject(Data("attest".utf8))
    public var attestationPayload: AttestationObject {
        get { lock.withLock { _attestationPayload } }
        set { lock.withLock { _attestationPayload = newValue } }
    }

    private var _assertionPayload = AppAttestAssertion(Data("assert".utf8))
    public var assertionPayload: AppAttestAssertion {
        get { lock.withLock { _assertionPayload } }
        set { lock.withLock { _assertionPayload = newValue } }
    }

    private var _generateKeyCalls = 0
    public var generateKeyCalls: Int {
        lock.withLock { _generateKeyCalls }
    }

    private var _attestKeyCalls = 0
    public var attestKeyCalls: Int {
        lock.withLock { _attestKeyCalls }
    }

    private var _generateAssertionCalls = 0
    public var generateAssertionCalls: Int {
        lock.withLock { _generateAssertionCalls }
    }

    // Optional error injection: when set, the corresponding call throws instead
    // of returning its stubbed payload. Used to exercise failure paths (e.g. a
    // DeviceCheck error from `generateAssertion`).
    private var _generateKeyError: Error?
    public var generateKeyError: Error? {
        get { lock.withLock { _generateKeyError } }
        set { lock.withLock { _generateKeyError = newValue } }
    }

    private var _attestKeyError: Error?
    public var attestKeyError: Error? {
        get { lock.withLock { _attestKeyError } }
        set { lock.withLock { _attestKeyError = newValue } }
    }

    private var _generateAssertionError: Error?
    public var generateAssertionError: Error? {
        get { lock.withLock { _generateAssertionError } }
        set { lock.withLock { _generateAssertionError = newValue } }
    }

    public init() {}

    /// Awaited before a key is minted, so a test can hold one attestation open and
    /// assert what another can do while it is held.
    ///
    /// Ordering asserted by holding, since a test that only checks outcomes cannot
    /// tell work that ran at once from work that was serialized.
    public var beforeGenerateKey: (@Sendable () async -> Void)? {
        get { lock.withLock { storedBeforeGenerateKey } }
        set { lock.withLock { storedBeforeGenerateKey = newValue } }
    }

    private var storedBeforeGenerateKey: (@Sendable () async -> Void)?

    public func generateKey() async throws -> AppAttestKeyId {
        // Counted on the way in, before the hook can hold the call, so the count
        // says how many callers asked rather than how many got an answer.
        lock.withLock { _generateKeyCalls += 1 }
        await beforeGenerateKey?()
        return try lock.withLock {
            if let error = _generateKeyError {
                throw error
            }
            return _generatedKeyId
        }
    }

    public func attestKey(_ keyId: AppAttestKeyId, clientDataHash: ClientDataHash) async throws -> AttestationObject {
        return try lock.withLock {
            _attestKeyCalls += 1
            if let error = _attestKeyError {
                throw error
            }
            return _attestationPayload
        }
    }

    /// Awaited before an assertion is produced, so a test can act inside the window
    /// the real call suspends for.
    public var beforeGenerateAssertion: (@Sendable () async -> Void)? {
        get { lock.withLock { storedBeforeGenerateAssertion } }
        set { lock.withLock { storedBeforeGenerateAssertion = newValue } }
    }

    private var storedBeforeGenerateAssertion: (@Sendable () async -> Void)?

    public func generateAssertion(_ keyId: AppAttestKeyId, clientDataHash: ClientDataHash) async throws -> AppAttestAssertion {
        await beforeGenerateAssertion?()
        return try lock.withLock {
            _generateAssertionCalls += 1
            if let error = _generateAssertionError {
                throw error
            }
            return _assertionPayload
        }
    }
}

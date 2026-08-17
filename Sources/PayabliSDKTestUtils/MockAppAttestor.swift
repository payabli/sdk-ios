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

    public func generateKey() async throws -> AppAttestKeyId {
        return try lock.withLock {
            _generateKeyCalls += 1
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

    public func generateAssertion(_ keyId: AppAttestKeyId, clientDataHash: ClientDataHash) async throws -> AppAttestAssertion {
        return try lock.withLock {
            _generateAssertionCalls += 1
            if let error = _generateAssertionError {
                throw error
            }
            return _assertionPayload
        }
    }
}

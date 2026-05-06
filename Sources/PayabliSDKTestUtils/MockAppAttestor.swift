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

    public init() {}

    public func generateKey() async throws -> AppAttestKeyId {
        return lock.withLock {
            _generateKeyCalls += 1
            return _generatedKeyId
        }
    }

    public func attestKey(_ keyId: AppAttestKeyId, clientDataHash: ClientDataHash) async throws -> AttestationObject {
        return lock.withLock {
            _attestKeyCalls += 1
            return _attestationPayload
        }
    }

    public func generateAssertion(_ keyId: AppAttestKeyId, clientDataHash: ClientDataHash) async throws -> AppAttestAssertion {
        return lock.withLock {
            _generateAssertionCalls += 1
            return _assertionPayload
        }
    }
}

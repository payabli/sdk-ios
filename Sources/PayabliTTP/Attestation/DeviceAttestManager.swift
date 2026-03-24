import Foundation
import DeviceCheck
import CryptoKit

/// Adapter: DeviceAttesting backed by Apple's DCAppAttestService.
/// Uses injected SecureStorage for keyId persistence (Keychain in prod, in-memory in tests).
final class DeviceAttestManager: DeviceAttesting {

    private static let keychainKeyId = "com.payabli.ttp.keyId"

    private let storage: SecureStorage
    private(set) var state: AttestationState

    init(storage: SecureStorage = KeychainStore()) {
        self.storage = storage
        if let storedKeyId = storage.loadString(key: Self.keychainKeyId) {
            state = .registered(keyId: storedKeyId)
        } else if Self.isSupported {
            state = .notRegistered
        } else {
            state = .unsupported
        }
    }

    static var isSupported: Bool {
        DCAppAttestService.shared.isSupported
    }

    // MARK: - Phase A: One-time registration

    func generateKey() async throws -> String {
        guard Self.isSupported else {
            throw PayabliTTPError.deviceNotSupported
        }
        return try await DCAppAttestService.shared.generateKey()
    }

    func attestKey(_ keyId: String, challenge: Data) async throws -> Data {
        guard Self.isSupported else {
            throw PayabliTTPError.deviceNotSupported
        }
        let clientDataHash = Data(SHA256.hash(data: challenge))
        return try await DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash)
    }

    func persistKeyId(_ keyId: String) throws {
        try storage.save(key: Self.keychainKeyId, string: keyId)
        state = .registered(keyId: keyId)
    }

    func discardKey() {
        storage.delete(key: Self.keychainKeyId)
        state = Self.isSupported ? .notRegistered : .unsupported
    }

    // MARK: - Phase B: Session assertions

    func generateAssertion(requestData: Data) async throws -> Data {
        guard case .registered(let keyId) = state else {
            throw PayabliTTPError.attestationFailed("No registered keyId. Device must be attested first.")
        }
        let clientDataHash = Data(SHA256.hash(data: requestData))
        do {
            return try await DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash)
        } catch let error as DCError where error.code == .invalidKey {
            // The Secure Enclave key is no longer valid (device migrated, restored from backup,
            // or Apple revoked it). Discard the persisted keyId so the next initialize()
            // triggers full Phase A re-attestation.
            discardKey()
            throw PayabliTTPError.attestationFailed("Attestation key invalidated by Apple. Re-attestation required.")
        }
    }

    // MARK: - Helpers

    var keyId: String? {
        if case .registered(let keyId) = state { return keyId }
        return nil
    }

    var needsAttestation: Bool {
        if case .notRegistered = state { return true }
        return false
    }
}

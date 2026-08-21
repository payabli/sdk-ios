import Foundation
import Security

/// Lightweight wrapper over the iOS Keychain for storing non-secret identity
/// tokens (PRD NFR-5E, §22.1).
///
/// Used by `AppAttestService` to persist `keyId` and `deviceId` across app
/// launches. **Must not** be used for true secrets (`clientSecret`, access
/// tokens, Fiserv credentials) — those live in RAM only (NFR-5D).
///
/// Items are stored as `kSecClassGenericPassword` with the SDK's bundle-level
/// service identifier so they're namespaced away from the host app's own
/// Keychain entries.
public struct KeychainStorage: SecureStorage, Sendable {
    public static let service = "com.payabli.sdk"

    /// Errors surfaced by Keychain operations. Tests may receive `.underlying`
    /// wrapping an `errSecXxx` OSStatus; on-device failures are typically
    /// transient (user locked device, etc.).
    public enum KeychainError: Swift.Error, Sendable {
        case underlying(OSStatus)
        case decoding
    }

    private let service: String

    public init(service: String = KeychainStorage.service) {
        self.service = service
    }

    // MARK: - Read

    public func string(forKey key: String) -> String? {
        guard let data = data(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    func data(forKey key: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess else { return nil }
        return item as? Data
    }

    // MARK: - Write

    public func set(_ value: String, forKey key: String) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.decoding
        }
        try set(data, forKey: key)
    }

    /// `AfterFirstUnlock` because the SDK reads these outside a foreground
    /// session. `ThisDeviceOnly` because `keyId` names a Secure Enclave key no
    /// backup carries, so a restored copy is an identity the new phone cannot
    /// sign for.
    private static let accessibility = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

    func set(_ data: Data, forKey key: String) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]

        // Update in place if it exists; otherwise add.
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: Self.accessibility
        ]
        var status = SecItemUpdate(baseQuery as CFDictionary, updateAttributes as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = Self.accessibility
            status = SecItemAdd(addQuery as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw KeychainError.underlying(status)
        }
    }

    // MARK: - Delete

    public func remove(forKey key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        _ = SecItemDelete(query as CFDictionary)
    }

    func removeAll() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        _ = SecItemDelete(query as CFDictionary)
    }
}

// MARK: - Storage keys used by the SDK (§22.1)

public enum PayabliKeychainKey {
    public static let keyId = "com.payabli.ttp.keyId"
    public static let deviceId = "com.payabli.ttp.deviceId"

    /// Holds a freshly generated App Attest key that has not yet completed
    /// attestation. Kept separate from `keyId` so a pre-attest retry can reuse
    /// the same Secure Enclave key without ever tripping `isAlreadyAttested`
    /// (which only consults `keyId` + `deviceId`).
    public static let pendingKeyId = "com.payabli.ttp.pendingKeyId"
}

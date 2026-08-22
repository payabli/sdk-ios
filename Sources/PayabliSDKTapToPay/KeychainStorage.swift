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

    /// Opening the store corrects what an older version of the SDK wrote, since
    /// nothing else will: see `migrateAccessibility(forKeys:)`.
    public init(service: String = KeychainStorage.service) {
        self.service = service
        migrateAccessibility(forKeys: PayabliKeychainKey.all)
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

    /// What both write paths carry, built once so neither can be given a
    /// different attribute from the other.
    static func writeAttributes(_ data: Data) -> [String: Any] {
        [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility
        ]
    }

    func set(_ data: Data, forKey key: String) throws {
        let baseQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        let attributes = Self.writeAttributes(data)

        // Update in place if it exists; otherwise add.
        var status = SecItemUpdate(baseQuery as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            status = SecItemAdd(baseQuery.merging(attributes) { _, new in new } as CFDictionary, nil)
        }
        guard status == errSecSuccess else {
            throw KeychainError.underlying(status)
        }
    }

    // MARK: - Migration

    /// Corrects the attribute on what is already stored, so an install that
    /// attested before this attribute existed stops being carried by a backup.
    ///
    /// Correcting an item is its next write, and the warm path only reads: a phone
    /// that has already attested never writes again, so without this it keeps the
    /// old attribute for as long as the install lasts.
    ///
    /// The attribute is changed on its own, without reading the value or writing it
    /// back. Reading and rewriting would let a value deleted in between be put back
    /// from the copy in hand, and `pendingKeyId` is deleted once attestation ends.
    ///
    /// Runs whenever the store is opened rather than once behind a flag, since the
    /// flag would be another stored item and a locked Keychain makes any single
    /// attempt a no-op. An item it cannot reach waits for the next one.
    func migrateAccessibility(forKeys keys: [String]) {
        for key in keys {
            let query: [String: Any] = [
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: key
            ]
            _ = SecItemUpdate(query as CFDictionary, [
                kSecAttrAccessible as String: Self.accessibility
            ] as CFDictionary)
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
    /// Holds a freshly generated App Attest key that has not yet completed
    /// attestation. Kept separate from the binding so a pre-attest retry can
    /// reuse the same Secure Enclave key without the warm path reading it as an
    /// enrolled device.
    public static let pendingKeyId = Stored.pendingKeyId.rawValue

    /// The keys themselves. The constants above are the names callers use, and a
    /// key added here joins `all` by being a case, so a sweep cannot miss one.
    /// Every binding this device holds, as one item. Replaces `keyId` and
    /// `deviceId`, which recorded no paypoint and were two writes with a window
    /// between them.
    public static let deviceBindings = Stored.deviceBindings.rawValue

    /// Written with its twin in the app container. The two are compared before a
    /// binding is trusted: the Keychain outlives app deletion and a Secure
    /// Enclave key does not.
    public static let installId = Stored.installId.rawValue

    enum Stored: String, CaseIterable {
        case deviceBindings = "com.payabli.ttp.deviceBindings"
        case pendingKeyId = "com.payabli.ttp.pendingKeyId"
        case installId = "com.payabli.ttp.installId"
    }

    /// What an install from before the bindings item may still be carrying. Read
    /// by nothing: the paypoint each belongs to was never recorded, so neither can
    /// be adopted, and they are removed the first time the store is opened.
    static let superseded = [
        "com.payabli.ttp.keyId",
        "com.payabli.ttp.deviceId"
    ]

    static let all = Stored.allCases.map(\.rawValue)
}

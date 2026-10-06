import Foundation
import Security

/// Lightweight wrapper over the iOS Keychain for storing non-secret identity
/// tokens (PRD NFR-5E, §22.1).
///
/// Holds the install identifier the session derives the device's identity from, and
/// the card-present module's bindings across app launches.
/// **Must not** be used for true secrets (`clientSecret`, access tokens, Fiserv
/// credentials) — those live in RAM only (NFR-5D).
///
/// Items are stored as `kSecClassGenericPassword` with the SDK's bundle-level
/// service identifier so they're namespaced away from the host app's own
/// Keychain entries.
package struct KeychainStorage: SecureStorage, Sendable {
    package static let service = "com.payabli.sdk"

    /// Errors surfaced by Keychain operations. Tests may receive `.underlying`
    /// wrapping an `errSecXxx` OSStatus; on-device failures are typically
    /// transient (user locked device, etc.).
    package enum KeychainError: Swift.Error, Sendable {
        case underlying(OSStatus)
        case decoding
    }

    private let service: String

    /// Opening the store corrects what an older version of the SDK wrote under `keys`,
    /// since nothing else will: see `migrateAccessibility(forKeys:)`.
    package init(service: String = KeychainStorage.service, migrating keys: [String]) {
        self.service = service
        migrateAccessibility(forKeys: keys)
    }

    // MARK: - Read

    package func string(forKey key: String) throws -> String? {
        guard let data = try data(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The stored bytes, `nil` when the item is not there, and a raise for every
    /// other answer the Keychain can give.
    ///
    /// `errSecItemNotFound` is the only status that means nothing is stored. The
    /// rest can pass: `errSecInteractionNotAllowed` is what a read gets before the
    /// first unlock after a boot, and answering `nil` there reports an enrolled
    /// device as a new one.
    package func data(forKey key: String) throws -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if Self.isMissing(status) {
            return nil
        }
        try Self.check(status)
        return item as? Data
    }

    /// The access group the item was written to, `nil` when the item is not there.
    package func accessGroup(forKey key: String) throws -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var item: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if Self.isMissing(status) {
            return nil
        }
        try Self.check(status)
        return (item as? [String: Any])?[kSecAttrAccessGroup as String] as? String
    }

    /// The only status that means nothing is stored, so the only one a read answers
    /// `nil` for.
    package static func isMissing(_ status: OSStatus) -> Bool {
        status == errSecItemNotFound
    }

    // MARK: - Write

    package func set(_ value: String, forKey key: String) throws {
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
    package static func writeAttributes(_ data: Data) -> [String: Any] {
        [
            kSecValueData as String: data,
            kSecAttrAccessible as String: accessibility
        ]
    }

    package func set(_ data: Data, forKey key: String) throws {
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

    /// Corrects the attribute on what is already stored, so an install that attested
    /// before this attribute existed stops being carried by a backup. Correcting an
    /// item is its next write, and a phone that has already attested never writes
    /// again.
    ///
    /// The attribute is changed on its own: reading the value and writing it back
    /// would restore one deleted in between, and `pendingKeyId` is deleted once
    /// attestation ends.
    ///
    /// Runs whenever the store is opened, since a locked Keychain makes any single
    /// attempt a no-op and an item it cannot reach waits for the next one.
    package func migrateAccessibility(forKeys keys: [String]) {
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

    /// Deleting what is not there is a success, so `errSecItemNotFound` passes: the
    /// caller asked for the item to be gone and it is.
    package func remove(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        try Self.check(SecItemDelete(query as CFDictionary))
    }

    package func removeAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        try Self.check(SecItemDelete(query as CFDictionary))
    }

    package static func check(_ status: OSStatus) throws {
        guard status != errSecSuccess, status != errSecItemNotFound else { return }
        throw KeychainError.underlying(status)
    }
}

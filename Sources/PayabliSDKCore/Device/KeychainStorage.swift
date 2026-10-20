import Foundation
import Security

/// Keychain wrapper for non-secret identity values: the install identifier and the card-present bindings,
/// stored as `kSecClassGenericPassword` under the SDK's own service, apart from the host app's entries.
/// **Must not** hold secrets (`clientSecret`, access tokens, Fiserv credentials), which live in RAM only.
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
    ///
    /// - Parameter service: the Keychain service the items are stored under, apart from the host app's entries.
    /// - Parameter keys: the account names an older version wrote, whose accessibility is corrected on open.
    package init(service: String = KeychainStorage.service, migrating keys: [String]) {
        self.service = service
        migrateAccessibility(forKeys: keys)
    }

    // MARK: - Read

    package func string(forKey key: String) throws -> String? {
        guard let data = try data(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The stored bytes, `nil` when the item is not there, and a raise for every other Keychain answer.
    /// `errSecInteractionNotAllowed`, what a read gets before the first unlock, raises so an
    /// enrolled device is not reported as a new one.
    ///
    /// - Parameter key: the account name the item is stored under, within the SDK's service.
    /// - Returns: the stored bytes, or `nil` only for `errSecItemNotFound`, the status that means none is stored.
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
    ///
    /// - Parameter key: the account name the item is stored under.
    /// - Returns: the item's `kSecAttrAccessGroup`, or `nil` when the item is not there.
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
    ///
    /// - Parameter status: the OSStatus the Keychain answered.
    /// - Returns: whether the status is `errSecItemNotFound`, the only one that means none is stored.
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
    ///
    /// - Parameter data: the bytes to store as the item's value.
    /// - Returns: the attributes both write paths carry, `data` with the shared device-only accessibility.
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

    /// Corrects the attribute on what is already stored, so an item an older version
    /// wrote stops being carried by a backup.
    /// The attribute is changed on its own, so a value deleted in between is not restored.
    ///
    /// - Parameter keys: the account names whose stored items are corrected; a locked Keychain leaves one for the next open.
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
    ///
    /// - Parameter key: the account name of the item to delete, whether or not it is stored.
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

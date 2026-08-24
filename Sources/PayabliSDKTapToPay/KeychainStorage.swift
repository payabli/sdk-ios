import Foundation
import Security

/// Lightweight wrapper over the iOS Keychain for storing non-secret identity
/// tokens (PRD NFR-5E, §22.1).
///
/// Used by `AppAttestService` to hold the device's bindings across app launches.
/// **Must not** be used for true secrets (`clientSecret`, access tokens, Fiserv
/// credentials) — those live in RAM only (NFR-5D).
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

    public func string(forKey key: String) throws -> String? {
        guard let data = try data(forKey: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// The stored bytes, `nil` when the item is not there, and a raise for every
    /// other answer the Keychain can give.
    ///
    /// `errSecItemNotFound` is the only status that means nothing is stored. The
    /// rest are conditions that can pass: `errSecInteractionNotAllowed` is what a
    /// read gets before the first unlock after a boot, and these items are written
    /// `AfterFirstUnlock`, so it is reachable by anything that runs that early.
    /// Answering `nil` there reports an enrolled device as a new one.
    func data(forKey key: String) throws -> Data? {
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

    /// The only status that means nothing is stored, so the only one a read answers
    /// `nil` for. Its own function because no test host here has a Keychain to
    /// answer with, and the list is what decides whether an enrolled device is
    /// reported as a new one.
    static func isMissing(_ status: OSStatus) -> Bool {
        status == errSecItemNotFound
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

    /// Deleting what is not there is a success, so `errSecItemNotFound` passes: the
    /// caller asked for the item to be gone and it is.
    public func remove(forKey key: String) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key
        ]
        try Self.check(SecItemDelete(query as CFDictionary))
    }

    func removeAll() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service
        ]
        try Self.check(SecItemDelete(query as CFDictionary))
    }

    static func check(_ status: OSStatus) throws {
        guard status != errSecSuccess, status != errSecItemNotFound else { return }
        throw KeychainError.underlying(status)
    }
}

// MARK: - Storage keys used by the SDK (§22.1)

public enum PayabliKeychainKey {
    /// Holds a freshly generated App Attest key that has not yet completed
    /// attestation. Kept separate from the binding so a pre-attest retry can
    /// reuse the same Secure Enclave key without the warm path reading it as an
    /// enrolled device.
    public static let pendingKeyId = Stored.pendingKeyId.rawValue

    /// Every binding this device holds, as one item. Replaces `keyId` and
    /// `deviceId`, which recorded no paypoint and were two writes with a window
    /// between them.
    public static let deviceBindings = Stored.deviceBindings.rawValue

    /// The keys themselves. The constants above are the names callers use, and a
    /// key added here joins `all` by being a case, so a sweep cannot miss one.
    enum Stored: String, CaseIterable {
        case deviceBindings = "com.payabli.ttp.deviceBindings"
        case pendingKeyId = "com.payabli.ttp.pendingKeyId"
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

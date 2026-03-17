import Foundation

/// Port: secure key-value storage for sensitive data (keyId, deviceId).
/// Production adapter: KeychainStore (iOS Keychain).
/// Test adapter: InMemorySecureStorage (dictionary).
protocol SecureStorage: Sendable {
    func save(key: String, data: Data) throws
    func load(key: String) -> Data?
    func delete(key: String)
}

extension SecureStorage {
    func save(key: String, string: String) throws {
        guard let data = string.data(using: .utf8) else {
            throw PayabliTTPError.attestationFailed("Failed to encode string for storage")
        }
        try save(key: key, data: data)
    }

    func loadString(key: String) -> String? {
        guard let data = load(key: key) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

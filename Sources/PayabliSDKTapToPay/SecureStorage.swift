import Foundation

/// Abstraction over a key/value store for non-secret identity tokens (§22.1).
///
/// Production uses `KeychainStorage` (iOS Keychain). Tests inject
/// `InMemorySecureStorage` from `PayabliSDKTestUtils`. The SDK depends only
/// on this protocol so it remains unit-testable without Keychain access.
public protocol SecureStorage: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String) throws
    func remove(forKey key: String)
}

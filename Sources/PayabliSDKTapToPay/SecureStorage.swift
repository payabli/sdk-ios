import Foundation

/// Abstraction over a key/value store for non-secret identity tokens (§22.1).
///
/// Production uses `KeychainStorage` (iOS Keychain). Tests inject
/// `InMemorySecureStorage` from `PayabliSDKTestUtils`. The SDK depends only
/// on this protocol so it remains unit-testable without Keychain access.
public protocol SecureStorage: Sendable {
    /// The value stored under `key`, or `nil` when nothing is stored under it now.
    ///
    /// `nil` is the current state and never a failure: a store that could not be
    /// read raises instead. Read as absent, an enrolled device registers a second
    /// time; read as present, a device with nothing stored can never start.
    ///
    /// A stored value that is not valid UTF-8 answers `nil`.
    func string(forKey key: String) throws -> String?

    func set(_ value: String, forKey key: String) throws

    /// Removes `key`. Succeeds whether or not anything was stored under it, and
    /// raises only when the store could not be reached.
    func remove(forKey key: String) throws
}

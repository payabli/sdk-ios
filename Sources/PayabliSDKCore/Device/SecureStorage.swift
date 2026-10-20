import Foundation

/// Key/value store for non-secret identity tokens. Production uses `KeychainStorage`; tests inject
/// `InMemorySecureStorage` from `PayabliSDKTestUtils`, so the SDK is unit-testable without Keychain access.
package protocol SecureStorage: Sendable {
    /// The value stored under `key`, or `nil` when nothing is stored under it now.
    /// `nil` is a state, never a failure: a store that could not be read raises instead. Read as
    /// absent, an enrolled device registers a second time; read as present, a device with nothing stored never starts.
    ///
    /// - Parameter key: the name the value is stored under.
    /// - Returns: the stored value, or `nil` when nothing is stored under it now or it is not valid UTF-8.
    func string(forKey key: String) throws -> String?

    func set(_ value: String, forKey key: String) throws

    /// Removes `key`. Succeeds whether or not anything was stored under it, and
    /// raises only when the store could not be reached.
    ///
    /// - Parameter key: the name of the value to remove, stored or not.
    func remove(forKey key: String) throws
}

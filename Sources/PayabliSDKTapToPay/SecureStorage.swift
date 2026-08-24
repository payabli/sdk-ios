import Foundation

/// Abstraction over a key/value store for non-secret identity tokens (§22.1).
///
/// Production uses `KeychainStorage` (iOS Keychain). Tests inject
/// `InMemorySecureStorage` from `PayabliSDKTestUtils`. The SDK depends only
/// on this protocol so it remains unit-testable without Keychain access.
public protocol SecureStorage: Sendable {
    /// The value stored under `key`, or `nil` when nothing is stored under it now.
    ///
    /// **`nil` is the current state, and never a failure.** A store that could not
    /// be read this time raises instead, because a caller that cannot tell the two
    /// apart has to guess, and both guesses are wrong: read as absent, a device
    /// that is already enrolled enrolls again and registers a second time; read as
    /// present, a device with nothing stored can never start.
    ///
    /// A stored value that is not valid UTF-8 answers `nil`. That is one entry
    /// being unreadable rather than the store failing, and the caller's own
    /// decoding already discards what it cannot parse.
    func string(forKey key: String) throws -> String?

    func set(_ value: String, forKey key: String) throws

    /// Removes `key`. Succeeds whether or not anything was stored under it.
    ///
    /// Raises only when the store could not be reached, so a caller that must know
    /// the value is gone can wait for it. A caller disposing of something already
    /// dead can ignore it.
    func remove(forKey key: String) throws
}

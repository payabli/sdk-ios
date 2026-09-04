import Foundation
import PayabliSDKTapToPay

/// In-memory `SecureStorage` implementation for tests.
///
/// Thread-safe via `NSLock`. Inject this as a `SecureStorage` dependency in
/// place of `KeychainStorage` so tests run without Keychain entitlements.
package final class InMemorySecureStorage: SecureStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: String] = [:]
    private var storedReadFailure: Error?

    package init() {}

    /// Raised by every read while it is set.
    ///
    /// Nothing in memory fails on its own, so without this the paths that separate
    /// a store holding nothing from one that could not be read are unreachable.
    package var readFailure: Error? {
        get {
            lock.lock()
            defer { lock.unlock() }
            return storedReadFailure
        }
        set {
            lock.lock()
            defer { lock.unlock() }
            storedReadFailure = newValue
        }
    }

    package func string(forKey key: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let storedReadFailure {
            throw storedReadFailure
        }
        return store[key]
    }

    package func set(_ value: String, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        store[key] = value
    }

    package func remove(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        store.removeValue(forKey: key)
    }
}

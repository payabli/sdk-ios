import Foundation
import PayabliSDKTapToPay

/// In-memory `SecureStorage` implementation for tests.
///
/// Thread-safe via `NSLock`. Inject this as a `SecureStorage` dependency in
/// place of `KeychainStorage` so tests run without Keychain entitlements.
public final class InMemorySecureStorage: SecureStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: String] = [:]
    private var storedReadFailure: Error?

    public init() {}

    /// Raised by every read while it is set.
    ///
    /// Nothing in memory fails on its own, so without this the paths that separate
    /// a store holding nothing from one that could not be read are unreachable in a
    /// test — and those are the paths that decide whether an enrolled device
    /// enrolls a second time.
    public var readFailure: Error? {
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

    public func string(forKey key: String) throws -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let storedReadFailure {
            throw storedReadFailure
        }
        return store[key]
    }

    public func set(_ value: String, forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        store[key] = value
    }

    public func remove(forKey key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        store.removeValue(forKey: key)
    }
}

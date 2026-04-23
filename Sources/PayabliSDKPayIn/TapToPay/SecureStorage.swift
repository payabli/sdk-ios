import Foundation

/// Abstraction over a key/value store for non-secret identity tokens (§22.1).
///
/// Production uses `KeychainStorage` (iOS Keychain). Tests use
/// `InMemorySecureStorage`. The SDK depends only on this protocol so it
/// remains unit-testable without Keychain access.
public protocol SecureStorage: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String) throws
    func remove(forKey key: String)
}

/// In-memory storage for tests. Not thread-safe beyond a single actor.
public final class InMemorySecureStorage: SecureStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: String] = [:]

    public init() {}

    public func string(forKey key: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return store[key]
    }

    public func set(_ value: String, forKey key: String) throws {
        lock.lock(); defer { lock.unlock() }
        store[key] = value
    }

    public func remove(forKey key: String) {
        lock.lock(); defer { lock.unlock() }
        store.removeValue(forKey: key)
    }
}


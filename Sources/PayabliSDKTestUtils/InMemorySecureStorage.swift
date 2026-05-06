import Foundation
import PayabliSDKTapToPay

/// In-memory `SecureStorage` implementation for tests.
///
/// Thread-safe via `NSLock`. Inject this as a `SecureStorage` dependency in
/// place of `KeychainStorage` so tests run without Keychain entitlements.
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

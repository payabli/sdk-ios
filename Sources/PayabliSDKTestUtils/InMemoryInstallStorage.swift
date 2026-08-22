import Foundation
import PayabliSDKTapToPay

/// In-memory `InstallScopedStorage` implementation for tests.
///
/// Thread-safe via `NSLock`. Inject this in place of
/// `UserDefaultsInstallStorage` so tests neither read nor write the running
/// process's defaults. Constructing a fresh one models an app reinstall: the
/// Keychain stub keeps its contents, this one starts empty.
public final class InMemoryInstallStorage: InstallScopedStorage, @unchecked Sendable {
    private let lock = NSLock()
    private var store: [String: String] = [:]

    public init() {}

    public func string(forKey key: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        return store[key]
    }

    public func set(_ value: String, forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        store[key] = value
    }

    public func remove(forKey key: String) {
        lock.lock()
        defer { lock.unlock() }
        store.removeValue(forKey: key)
    }
}

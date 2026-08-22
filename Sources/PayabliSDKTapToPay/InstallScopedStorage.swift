import Foundation

/// A small string store whose contents die with the app installation.
///
/// The counterpart to `SecureStorage`, and the difference in lifetime is the
/// whole point. Keychain items outlive app deletion; the app container does
/// not. Attestation state found in the Keychain with no matching record here
/// was therefore left behind by a previous installation, whose Secure Enclave
/// App Attest key is gone and cannot be signed with again.
///
/// Nothing confidential belongs here. It holds one opaque installation
/// identifier, and its only job is to disappear.
public protocol InstallScopedStorage: Sendable {
    func string(forKey key: String) -> String?
    func set(_ value: String, forKey key: String)
    func remove(forKey key: String)
}

/// `UserDefaults`-backed `InstallScopedStorage`, which is the store that gives
/// the required lifetime: it lives in the app container, so iOS removes it
/// with the app.
public struct UserDefaultsInstallStorage: InstallScopedStorage, @unchecked Sendable {
    /// `UserDefaults` is documented as thread-safe but is not `Sendable`.
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func string(forKey key: String) -> String? {
        defaults.string(forKey: key)
    }

    public func set(_ value: String, forKey key: String) {
        defaults.set(value, forKey: key)
    }

    public func remove(forKey key: String) {
        defaults.removeObject(forKey: key)
    }
}

// MARK: - Storage keys

public enum PayabliInstallKey {
    /// Mirrors `PayabliKeychainKey.installId`. The two are written together and
    /// compared on every cold attestation; a disagreement means this container
    /// is younger than the Keychain, so the attestation state is a previous
    /// installation's and cannot be used.
    public static let installId = "com.payabli.ttp.install.installId"
}

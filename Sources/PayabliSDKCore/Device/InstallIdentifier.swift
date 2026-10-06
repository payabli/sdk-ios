import CryptoKit
import Foundation

/// This device's identity: what `PayabliSession.deviceId` answers and `/register` receives as `hardwareId`.
///
/// Half a SHA-256 over a Keychain UUID, the bundle identifier and the SDK identifier. The UUID is kept
/// in the Keychain because it survives a reinstall, which `identifierForVendor` does not. Changing any
/// input registers every install as a new device. Blank when there is nothing to build from.
package enum InstallIdentifier {
    static let sdkIdentifier = "com.payabli.sdk"

    package static let storageKey = "com.payabli.ttp.installId"

    /// Opened on first use, once per process, so a read that keeps failing does not reopen the store.
    static let store = KeychainStorage(migrating: [storageKey])

    /// One lock for every caller in the process, so two entry points enrolling at
    /// once cannot mint two UUIDs and register two devices for one install.
    private static let lock = NSLock()

    package static func hardwareId(
        storage: SecureStorage,
        bundleIdentifier: String? = Bundle.main.bundleIdentifier
    ) throws -> String {
        guard let bundleIdentifier, !bundleIdentifier.isEmpty else { return "" }

        let install = try lock.withLock { try installValue(storage: storage) }
        guard !install.isEmpty else { return "" }

        let material = "\(install)|\(bundleIdentifier)|\(sdkIdentifier)"
        let digest = SHA256.hash(data: Data(material.utf8))
        return digest.prefix(identifierBytes).map { String(format: "%02x", $0) }.joined()
    }

    private static let identifierBytes = 16

    /// Read under the lock, and minted there when the read finds nothing, so the
    /// value one caller writes is the value every later caller reads.
    private static func installValue(storage: SecureStorage) throws -> String {
        if let existing = try storage.string(forKey: storageKey),
           !existing.isEmpty
        {
            return existing
        }
        let minted = UUID().uuidString
        try storage.set(minted, forKey: storageKey)
        return minted
    }
}

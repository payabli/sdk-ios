import CryptoKit
import Foundation

/// The value `/register` is given to recognize this install across registrations.
///
/// It has to be the same on every call, stable across an uninstall and reinstall,
/// and different per app: two apps from one developer on one handset are two
/// devices, and nothing else sent alongside this tells them apart. The platform's
/// vendor identifier is one value for every app from the same vendor.
///
/// So it is a digest of three things:
///
/// - a UUID minted once and kept in the Keychain, which is what survives a
///   reinstall, since Keychain items outlive the app's container;
/// - the bundle identifier, which makes it per app and keeps the answer independent
///   of which Keychain access group the UUID lands in;
/// - this module's own name, so a second SDK reading the same UUID cannot compute
///   the same value.
///
/// The digest is sent, never the UUID, truncated to 128 bits. A blank is returned
/// when there is nothing to build from: a value invented per call is not an
/// identifier.
enum InstallIdentifier {
    /// Mixed into the digest so this module's value cannot be recomputed by another
    /// one reading the same stored UUID.
    static let sdkIdentifier = "com.payabli.sdk.taptopay"

    /// One lock for every caller in the process, so two entry points enrolling at
    /// once cannot mint two UUIDs and register two devices for one install.
    private static let lock = NSLock()

    static func hardwareId(
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

    /// Half the digest.
    private static let identifierBytes = 16

    /// Read under the lock, and minted there when the read finds nothing, so the
    /// value one caller writes is the value every later caller reads.
    private static func installValue(storage: SecureStorage) throws -> String {
        if let existing = try storage.string(forKey: PayabliKeychainKey.installId),
           !existing.isEmpty
        {
            return existing
        }
        let minted = UUID().uuidString
        try storage.set(minted, forKey: PayabliKeychainKey.installId)
        return minted
    }
}

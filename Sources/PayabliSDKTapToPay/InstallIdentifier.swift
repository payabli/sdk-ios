import CryptoKit
import Foundation

/// The value `/register` is given to recognize this install across registrations.
///
/// Two properties decide whether a returning install is recognized as itself, and
/// both are easy to lose. It has to be **the same on every call**, or each call
/// looks like a different install. And it has to be **stable across an uninstall
/// and reinstall**, or a returning install looks like one that has never been seen.
///
/// **It also has to differ per app.** Two apps from one developer on one handset
/// are two devices, and nothing else sent alongside this tells them apart. The
/// platform's vendor identifier cannot express that: it is one value for every app
/// from the same vendor, so both would be indistinguishable. The sibling SDK mixes
/// its package name in for the same reason.
///
/// So the identifier is a digest of three things:
///
/// - a UUID minted once and kept in the Keychain, which is what survives a
///   reinstall, since Keychain items outlive the app's container;
/// - the bundle identifier, which is what makes it per app;
/// - this module's own name, so a second SDK reading the same UUID cannot compute
///   the same value.
///
/// Mixing the bundle identifier in also makes the answer independent of which
/// Keychain access group the UUID lands in. A host that shares a group with a
/// sibling app lets that app read the UUID, and it still cannot produce this
/// value, because its bundle identifier is not this one.
///
/// **The digest is sent, never the UUID.** It has the same lifetime and keeps the
/// stored value on the device, so a party holding only the digest cannot recover
/// it. Truncated to 128 bits, which is far past collision concerns for a lookup on
/// one paypoint, and the wire field is sized for a serial number.
///
/// A blank is returned when there is nothing to build from. Substituting a random
/// value is what an earlier revision did, and it is why every call looked like a
/// different install: a value invented per call is not an identifier.
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

    /// Half the digest. See the note on truncation above.
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

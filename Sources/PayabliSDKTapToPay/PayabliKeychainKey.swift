import PayabliSDKCore

// MARK: - Storage keys used by the SDK

package enum PayabliKeychainKey {
    /// Holds a freshly generated App Attest key that has not yet completed
    /// attestation. Kept separate from the binding so a pre-attest retry can
    /// reuse the same Secure Enclave key without the warm path reading it as an
    /// enrolled device.
    package static let pendingKeyId = Stored.pendingKeyId.rawValue

    /// Every binding this device holds, as one item. Replaces `keyId` and
    /// `deviceId`, which recorded no paypoint and were two writes with a window
    /// between them.
    package static let deviceBindings = Stored.deviceBindings.rawValue

    /// The UUID this install was first seen with, which the device's identity is
    /// derived from. Core owns it; it is here so the sweep below reaches it.
    package static let installId = InstallIdentifier.storageKey

    /// The keys themselves. The constants above are the names callers use, and a
    /// key added here joins `all` by being a case, so a sweep cannot miss one.
    enum Stored: String, CaseIterable {
        case deviceBindings = "com.payabli.ttp.deviceBindings"
        case pendingKeyId = "com.payabli.ttp.pendingKeyId"
    }

    /// What an install from before the bindings item may still be carrying. Read
    /// by nothing: the paypoint each belongs to was never recorded, so neither can
    /// be adopted, and they are removed when the binding store is opened.
    static let superseded = [
        "com.payabli.ttp.keyId",
        "com.payabli.ttp.deviceId"
    ]

    static let all = Stored.allCases.map(\.rawValue) + [installId]
}

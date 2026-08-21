import Foundation

/// The attestation binding this device holds: which paypoint, which device
/// handle, which key.
///
/// A handle is issued for one paypoint and says nothing about another, so a
/// session holding one and configured for the other is not enrolled and must be
/// told so. Presenting it anyway is refused, and the refusal is indistinguishable
/// from a revoked attestation, which costs the device its enrolment.
///
/// A cache, not a credential. Every field is identity and none is secret;
/// the authority sits with a Secure Enclave key that cannot leave the device.
///
/// The description prints nothing: `entry` names a merchant.
struct AttestedDevice: Codable, Equatable, CustomStringConvertible, Sendable {
    /// The paypoint this binding is against.
    let entry: String
    /// The handle the device was registered under. Not derivable, which is the
    /// reason to keep it.
    let deviceId: String
    /// The App Attest key that was attested.
    let keyId: String

    var description: String {
        "AttestedDevice()"
    }
}

/// Every binding this device holds, one per entry point, most recently used
/// first.
///
/// A device is issued its own handle for each entry point it enrolls against, so
/// one binding cannot stand for another and keeping only the newest strands the
/// rest. The order is the whole retention rule: the front is the binding used
/// last, and anything past `maximum` falls off the back.
///
/// An array rather than a dictionary, because the order carries the meaning and a
/// dictionary would leave it resting on whatever order the decoder built. Lookup
/// is by entry point either way, and at this size a scan costs nothing.
///
/// No field records when a binding was last used, and none should be added: a
/// position says which is coldest without a clock the SDK does not control.
///
/// The description prints nothing: every entry point names a merchant.
struct DeviceBindings: Codable, Equatable, CustomStringConvertible, Sendable {
    /// How many entry points one install keeps. Enough for a device moved
    /// between paypoints to find each where it left it, few enough that the
    /// oldest is genuinely cold.
    static let maximum = 4

    let bindings: [AttestedDevice]

    var description: String {
        "DeviceBindings(count: \(bindings.count))"
    }

    init(_ bindings: [AttestedDevice] = []) {
        self.bindings = bindings
    }

    func binding(for entry: String) -> AttestedDevice? {
        bindings.first { $0.entry == entry }
    }

    /// `record` at the front, replacing any binding for the same entry point.
    func with(_ record: AttestedDevice) -> DeviceBindings {
        DeviceBindings(([record] + bindings.filter { $0.entry != record.entry }).prefix(Self.maximum).map { $0 })
    }

    func without(entry: String) -> DeviceBindings {
        DeviceBindings(bindings.filter { $0.entry != entry })
    }
}

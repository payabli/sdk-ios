import Foundation

/// The attestation binding this device holds: which paypoint, which device
/// handle, which key.
///
/// A handle is issued for one paypoint and says nothing about another, so a
/// session holding one and configured for the other is not enrolled. Presenting it
/// anyway is refused, and the refusal costs the device its enrolment.
///
/// A cache, not a credential: every field is identity, and the authority sits with
/// a Secure Enclave key that cannot leave the device.
///
/// The description prints nothing: `entry` names a merchant.
struct AttestedDevice: Codable, Equatable, CustomStringConvertible, Sendable {
    /// The paypoint this binding is against.
    let entry: String
    /// The handle the device was registered under.
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
/// keeping only the newest strands the rest. The order is the whole retention rule:
/// the front is the binding used last, and anything past `maximum` falls off the
/// back. An array, so the order does not rest on whatever order a decoder built.
///
/// No field records when a binding was last used, and none should be added: a
/// position says which is coldest without a clock the SDK does not control.
///
/// The description prints nothing: every entry point names a merchant.
struct DeviceBindings: Codable, Equatable, CustomStringConvertible, Sendable {
    /// How many entry points one install keeps.
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

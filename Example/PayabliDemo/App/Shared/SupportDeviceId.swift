/// The device ID support asks for, as the Config tab shows it.
///
/// Its description says only whether it holds an ID: a synthesized one would print it.
struct SupportDeviceId: CustomStringConvertible, CustomDebugStringConvertible {
    /// The ID to copy, or `nil` when there is none.
    let copyable: String?

    /// - Parameter deviceId: the session's `deviceId`.
    init(_ deviceId: String?) {
        copyable = deviceId?.isEmpty == false ? deviceId : nil
    }

    /// The row's value: the ID, or "Unavailable".
    var shown: String {
        copyable ?? "Unavailable"
    }

    var description: String {
        "SupportDeviceId(hasDeviceId: \(copyable != nil))"
    }

    var debugDescription: String {
        description
    }
}

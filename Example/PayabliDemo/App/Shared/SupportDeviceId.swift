/// The device ID support asks for, as the Config tab shows it.
///
/// Its description says only whether it holds an ID: a synthesized one would print it.
struct SupportDeviceId: CustomStringConvertible, CustomDebugStringConvertible {
    /// Before the session has answered.
    static let reading = SupportDeviceId(copyable: nil, isAnswered: false)

    /// The ID to copy, or `nil` when there is none.
    let copyable: String?

    private let isAnswered: Bool

    /// - Parameter deviceId: the session's answer.
    init(_ deviceId: String?) {
        self.init(copyable: deviceId, isAnswered: true)
    }

    private init(copyable: String?, isAnswered: Bool) {
        self.copyable = copyable
        self.isAnswered = isAnswered
    }

    /// The row's value: "Reading…" until the session answers, then the ID or "Unavailable".
    var shown: String {
        guard isAnswered else { return "Reading…" }
        return copyable ?? "Unavailable"
    }

    var description: String {
        "SupportDeviceId(isAnswered: \(isAnswered), hasDeviceId: \(copyable != nil))"
    }

    var debugDescription: String {
        description
    }
}

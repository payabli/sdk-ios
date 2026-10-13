import Foundation

/// Which Payabli environment this build talks to.
///
/// This app's own, so a screen holds no SDK type. The list a build offers is
/// built in `SDK/` and handed in.
struct DemoEnvironment: Hashable {
    /// What the scheme passes and what a screen shows.
    let label: String

    let baseURL: URL

    var host: String? {
        baseURL.host
    }

    /// Every label, for a message that has to list them.
    static func labels(of offered: [DemoEnvironment]) -> String {
        offered.map(\.label).joined(separator: ", ")
    }

    /// The environment of `offered` a label names, or nil when none does.
    /// Trimmed and case-insensitive, for a value typed by hand into a scheme.
    static func named(_ label: String, in offered: [DemoEnvironment]) -> DemoEnvironment? {
        let wanted = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return offered.first { $0.label == wanted }
    }
}

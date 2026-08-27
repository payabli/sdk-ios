import Foundation

/// Which Payabli environment this build talks to.
///
/// This app's own, so a screen showing which service it points at holds no SDK
/// type. The SDK group converts it in one place, where a session is built.
enum DemoEnvironment: String, CaseIterable {
    case qa
    case sandbox
    case production

    /// What the scheme passes and what a screen shows.
    var label: String {
        rawValue
    }

    var baseURL: URL {
        // swiftlint:disable force_unwrapping
        switch self {
        case .qa: return URL(string: "https://api-qa.payabli.com")!
        case .sandbox: return URL(string: "https://api-sandbox.payabli.com")!
        case .production: return URL(string: "https://api.payabli.com")!
        }
        // swiftlint:enable force_unwrapping
    }

    var host: String? {
        baseURL.host
    }

    /// The one configured by default, and what an unrecognised setting falls back
    /// to. Sandbox, as the environment an integrator can reach.
    static let fallback = DemoEnvironment.sandbox

    /// Every label, for a message that has to list them.
    static var labels: String {
        allCases.map(\.label).joined(separator: ", ")
    }

    /// The environment a label names, or nil when nothing does. Trimmed and
    /// case-insensitive, for a value typed by hand into a scheme.
    static func named(_ label: String) -> DemoEnvironment? {
        let wanted = label.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return allCases.first { $0.label == wanted }
    }
}

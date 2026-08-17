import Foundation

/// The Payabli API environment used by the SDK.
///
/// Determines all API base URLs. Set at initialization via `PayabliConfig`.
/// See PRD §8.2 for base URLs.
@objc public enum PayabliEnvironment: Int, Sendable {
    #if DEBUG
        /// Developer-only environment pointing at a local tunnel. Available only
        /// in DEBUG builds — never shipped in a release binary.
        case local = 0
    #endif
    case qa = 1
    case sandbox = 2
    case production = 3

    /// Base URL for this environment.
    public var baseURL: URL {
        // swiftlint:disable force_unwrapping
        switch self {
        #if DEBUG
            case .local:
                return URL(string: "https://wallets-test.ngrok.app")!
        #endif
        case .qa:
            return URL(string: "https://api-qa.payabli.com")!
        case .sandbox:
            return URL(string: "https://api-sandbox.payabli.com")!
        case .production:
            return URL(string: "https://api.payabli.com")!
        }
        // swiftlint:enable force_unwrapping
    }
}

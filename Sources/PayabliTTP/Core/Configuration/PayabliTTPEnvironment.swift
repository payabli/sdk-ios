import Foundation

public enum PayabliTTPEnvironment: Sendable {
    case qa
    case sandbox
    case production

    var baseURL: URL {
        switch self {
        case .qa:
            return URL(string: "https://api-qa.payabli.com")!
        case .sandbox:
            return URL(string: "https://api-sandbox.payabli.com")!
        case .production:
            return URL(string: "https://api.payabli.com")!
        }
    }
}
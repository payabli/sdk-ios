import Foundation
@testable import PayabliSDKCore

/// What a build added, for the flow tests. The app reads its own from the
/// gitignored `ExtraEnvironments.swift`.
enum ExtraEnvironments {
    static let added = [PayabliEnvironment(name: "staging", baseURL: URL(string: "https://api-staging.payabli.com")!)]
}

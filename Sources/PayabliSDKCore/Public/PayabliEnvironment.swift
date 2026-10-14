import Foundation

/// The Payabli API environment used by the SDK.
///
/// Determines the base URL every request resolves against. Set at
/// initialization via `PayabliConfig`.
///
/// `sandbox` and `production` are the whole of what the committed source
/// offers. The initializer is module-internal, so no host code can construct
/// an environment or repoint a committed origin. Instances are created once,
/// so equality is identity.
@objc public final class PayabliEnvironment: NSObject, Sendable {
    /// The identifier, lowercase.
    public let name: String

    /// Base URL for this environment.
    public let baseURL: URL

    /// The identifier, so a printed configuration names its environment.
    override public var description: String {
        name
    }

    init(name: String, baseURL: URL) {
        self.name = name
        self.baseURL = baseURL
    }

    /// The two committed environments, `sandbox` first.
    public static var entries: [PayabliEnvironment] {
        [sandbox, production]
    }

    /// The environment an integrator verifies against.
    @objc public static let sandbox = PayabliEnvironment(name: "sandbox", baseURL: URL(string: "https://api-sandbox.payabli.com")!)

    /// The live environment.
    @objc public static let production = PayabliEnvironment(name: "production", baseURL: URL(string: "https://api.payabli.com")!)
}

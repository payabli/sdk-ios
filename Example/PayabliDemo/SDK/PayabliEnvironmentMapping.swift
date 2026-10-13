import PayabliSDKCore

/// The one place the app's environment and the SDK's meet. Nothing above here
/// holds an SDK type to point a session somewhere.
extension DemoEnvironment {
    /// The app's view of an SDK environment: its name and where it points.
    init(_ environment: PayabliEnvironment) {
        self.init(label: environment.name, baseURL: environment.baseURL)
    }

    static let sandbox = DemoEnvironment(PayabliEnvironment.sandbox)

    static let production = DemoEnvironment(PayabliEnvironment.production)

    /// The one run when nothing chose another. Sandbox, as the environment an
    /// integrator can reach.
    static let fallback = sandbox

    /// Whether this one reaches production's host, whatever a build named it.
    var pointsAtProduction: Bool {
        host == DemoEnvironment.production.host
    }
}

/// Which SDK this build links, for the Config tab.
enum PayabliSDKBuild {
    static var version: String {
        PayabliCore.version
    }
}

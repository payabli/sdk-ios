import PayabliSDKCore

/// The SDK's name for the environment this demo is pointed at.
///
/// The one place the two meet. The app decides which environment it runs against
/// and shows it; this says what the SDK calls it, so nothing above has to hold an
/// SDK type to point a session somewhere.
extension DemoEnvironment {
    var sdkEnvironment: PayabliEnvironment {
        switch self {
        case .qa: return .qa
        case .sandbox: return .sandbox
        case .production: return .production
        }
    }
}

/// Which SDK this build links, for the Config tab.
enum PayabliSDKBuild {
    static var version: String {
        PayabliCore.version
    }
}

import Foundation

/// Starts the session from Objective-C, which can hold neither `PayabliSession` nor `PayabliConfig`.
///
/// It installs the same session `PayabliSession.initialize(config:)` does, so a host bridging both
/// languages runs one session whichever starts it.
private let sessionErrorDomain = "com.payabli.session"

@objc(PayabliSessionObjC)
public final class PayabliSessionObjC: NSObject {
    @available(*, unavailable)
    override private init() {
        fatalError("unavailable")
    }

    /// The bridged form of `PayabliSession.initialize(config:)`.
    ///
    /// `tokenHandler` receives a `(token, error) -> Void` callback the host calls exactly once, with
    /// either an access token or an `NSError`.
    @objc public static func initialize(
        tokenHandler: @escaping (@escaping (String?, NSError?) -> Void) -> Void,
        entryPoint: String,
        environment: PayabliEnvironment,
        telemetryEnabled: Bool
    ) async throws {
        do {
            let config = try PayabliConfig(
                entryPoint: entryPoint,
                environment: environment,
                tokenProvider: bridgedTokenProvider(errorDomain: sessionErrorDomain, tokenHandler),
                telemetryEnabled: telemetryEnabled
            )
            try await PayabliSession.initialize(config: config)
        } catch {
            throw error.payabliNSError(domain: sessionErrorDomain)
        }
    }
}

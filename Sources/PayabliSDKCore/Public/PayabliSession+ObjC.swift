import Foundation

/// Starts the session from Objective-C, which can hold neither `PayabliSession` nor `PayabliConfig`.
///
/// It installs the same session `PayabliSession.initialize(config:)` does, so a host bridging both
/// languages runs one session whichever starts it.
@objc(PayabliSessionObjC)
public final class PayabliSessionObjC: NSObject {
    @available(*, unavailable)
    override private init() {
        fatalError("unavailable")
    }

    /// The installed session's `deviceId`, and also `nil` before `initialize` has run.
    @objc public static var deviceId: String? {
        PayabliSession.current?.deviceId
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
        let config = try PayabliConfig(
            entryPoint: entryPoint,
            environment: environment,
            tokenProvider: bridgedTokenProvider(errorDomain: "com.payabli.session", tokenHandler),
            telemetryEnabled: telemetryEnabled
        )
        try await PayabliSession.initialize(config: config)
    }
}

import Foundation

/// A shared session backbone used by every PayabliSDK component instance
/// that targets the same `PayabliConfig`.
///
/// Owns exactly one `PayabliAuth` and one `PayabliService` for the
/// lifetime of the host app's interaction with Payabli on a given config.
/// Components (today: `PayabliTTP`; tomorrow: `PayabliPayIn`) accept a
/// `PayabliSession` so token refreshes, rate limits, and telemetry hooks
/// live in one place rather than per-facade.
///
/// Construct one explicitly when you intend to share auth across modules:
///
/// ```swift
/// let session = PayabliSession(config: config)
/// let ttp = PayabliTTP(session: session, appId: "...", ...)
/// // Later, when PayIn lands:
/// // let payIn = PayabliPayIn(session: session, ...)
/// ```
///
/// The convenience inits on each component facade build a
/// `PayabliSession` internally — single-component apps do not have to
/// touch this type.
public final class PayabliSession: @unchecked Sendable {
    public let config: PayabliConfig
    public let auth: PayabliAuth
    public let service: PayabliService

    public init(config: PayabliConfig, urlSession: URLSession? = nil) {
        self.config = config
        self.auth = PayabliAuth(config: config)
        self.service = PayabliService(
            environment: config.environment,
            session: urlSession
        )
    }
}

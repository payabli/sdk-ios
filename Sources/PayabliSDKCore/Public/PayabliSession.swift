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
    /// The configuration this session was constructed with.
    public let config: PayabliConfig

    /// The shared authentication actor for this session. Holds the
    /// current access token and deduplicates concurrent refreshes.
    /// Subscribe to `auth.tokenChanges()` to observe rotations.
    public let auth: PayabliAuth

    /// The transport every endpoint client consumes: its chain attaches the credential, and it adds
    /// 401 refresh-and-retry over that. The undecorated transport underneath is not exposed.
    public let transport: any PayabliTransport

    public init(config: PayabliConfig, urlSession: URLSession? = nil) {
        self.config = config
        let auth = PayabliAuth(config: config)
        self.auth = auth
        let service = PayabliService(
            environment: config.environment,
            readToken: { await auth.currentAccessToken() },
            session: urlSession
        )
        self.transport = AuthenticatedTransport(base: service, auth: auth)
    }
}

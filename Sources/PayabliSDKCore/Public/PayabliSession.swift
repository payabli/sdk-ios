import Foundation

/// The session backbone a component facade runs on.
///
/// Owns one credential holder and one transport for the lifetime of the host app's
/// interaction with Payabli on a given config, so token refreshes, rate limits and
/// telemetry hooks live in one place rather than per-request.
///
/// The initializers that take a session rather than building one are `package`, so a
/// shared session is reachable from a capability target and not from a host app. A host
/// builds a facade from an access token and an entry point, and the facade builds the
/// session.
///
/// Two facades do not share one today. The card-present facade's public initializers
/// build a fresh session, and the card-not-present facade takes its own token provider and
/// builds its own transport, so an app using both holds two sets of credential state.
/// Converging them changes what an integrator supplies and is tracked separately.
public final class PayabliSession: @unchecked Sendable {
    /// The configuration this session was constructed with.
    public let config: PayabliConfig

    /// Holds the current access token and deduplicates concurrent refreshes. Nothing outside
    /// this module reaches it, and nothing at any visibility hands the token to a host app.
    let auth: PayabliAuth

    /// The transport every endpoint client consumes: its chain attaches the credential, and it adds
    /// 401 refresh-and-retry over that. The undecorated transport underneath is not exposed.
    ///
    /// `package`, so a capability target can reach it and a host app cannot.
    package let transport: any PayabliTransport

    public init(config: PayabliConfig, urlSession: URLSession? = nil) {
        self.config = config
        let auth = PayabliAuth(config: config)
        self.auth = auth
        let service = PayabliService(
            environment: config.environment,
            readToken: { await auth.currentAccessToken() },
            session: urlSession
        )
        self.transport = AuthenticatedTransport(
            base: service,
            auth: auth,
            logger: PayabliLogger(category: .network)
        )
    }
}

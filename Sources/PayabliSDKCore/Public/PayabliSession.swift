import Foundation

/// The session backbone a component facade runs on.
///
/// Owns one credential holder and one transport for the lifetime of the host app's
/// interaction with Payabli on a given config, so token refreshes, rate limits and
/// telemetry hooks live in one place rather than per-request.
///
/// A host builds one from a `PayabliConfig` and hands it to the card-not-present facade,
/// whose initializer takes it. The card-present facade takes a provider and an entry point
/// and builds its own.
///
/// So two facades do not share one today: an app using both holds two sessions and two sets
/// of credential state. Giving the card-present facade the same session-taking shape changes
/// what an integrator supplies and is tracked separately.
public final class PayabliSession: @unchecked Sendable {
    /// The configuration this session was constructed with.
    ///
    /// `package`, so a capability target can read the entry point and the environment it is running
    /// against and a host app cannot read the configuration back out of the session.
    package let config: PayabliConfig

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
            readToken: { try await auth.currentAccessToken() },
            session: urlSession
        )
        self.transport = AuthenticatedTransport(
            base: service,
            auth: auth,
            logger: PayabliLogger(category: .network)
        )
    }
}

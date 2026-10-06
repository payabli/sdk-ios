import Foundation

/// The session every capability facade runs on: one credential holder and one transport per process.
///
/// A host installs it with `initialize(config:)` and each facade finds it underneath, so token
/// refreshes and 401 recovery live in one place. Two holders would each refresh on their own, and a
/// refresh one of them deduplicated is invisible to the other.
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

    /// This device's identity, the same for every capability and stable for the install. `nil` while
    /// the device's secure store cannot be read, such as before the first unlock after a restart.
    public var deviceId: String? {
        guard let value = try? deviceIdentity.value(), !value.isEmpty else { return nil }
        return value
    }

    package let deviceIdentity: DeviceIdentity

    private let identity: ConfigIdentity

    /// A process-wide lock, because the installed session is process-wide.
    private static let lock = NSLock()
    private static var installed: PayabliSession?

    init(
        config: PayabliConfig,
        urlSession: URLSession? = nil,
        deviceIdentity: DeviceIdentity = DeviceIdentity {
            try InstallIdentifier.hardwareId(storage: KeychainStorage(migrating: [InstallIdentifier.storageKey]))
        }
    ) {
        self.config = config
        self.deviceIdentity = deviceIdentity
        identity = ConfigIdentity(config)
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

    /// Installs the process's session, or returns it if one is already installed for an equal
    /// configuration.
    ///
    /// Configurations are equal when their entry point, environment and telemetry setting are. The
    /// token provider is not compared, so a second call keeps the provider the session started with.
    /// A different configuration throws `invalidConfiguration` and leaves the installed session in
    /// place, because every facade already built is running on it.
    @discardableResult
    public static func initialize(config: PayabliConfig) async throws -> PayabliSession {
        try install(config: config)
    }

    static func install(config: PayabliConfig, urlSession: URLSession? = nil) throws -> PayabliSession {
        try lock.withLock {
            let identity = ConfigIdentity(config)
            if let current = installed {
                guard current.identity == identity else {
                    throw PayabliGenericError(
                        type: .invalidConfiguration,
                        reason: "a session is already initialized with a different configuration"
                    )
                }
                return current
            }
            let session = PayabliSession(config: config, urlSession: urlSession)
            installed = session
            return session
        }
    }

    /// Whether `config` describes this session, by the same rule `initialize` applies.
    package func matches(_ config: PayabliConfig) -> Bool {
        identity == ConfigIdentity(config)
    }

    /// The installed session, if `initialize` has run.
    package static var current: PayabliSession? {
        lock.withLock { installed }
    }

    static func resetForTesting() {
        lock.withLock { installed = nil }
    }
}

/// The parts of a configuration that decide whether two describe the same session.
///
/// A provider is a closure and has no identity worth comparing: an inline one is new on every call.
private struct ConfigIdentity: Equatable {
    let entryPoint: String
    let environment: PayabliEnvironment
    let telemetryEnabled: Bool

    init(_ config: PayabliConfig) {
        entryPoint = config.entryPoint
        environment = config.environment
        telemetryEnabled = config.telemetryEnabled
    }
}

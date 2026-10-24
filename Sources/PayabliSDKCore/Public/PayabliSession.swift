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

    /// This device's identity, the same for every capability. Stable across reinstalls; a device wipe, or moving
    /// to another phone even from a backup, gives it a new one. `nil` while the device's secure store cannot be
    /// read, such as before the first unlock after a restart.
    public var deviceId: String? {
        guard let value = try? deviceIdentity.value(), !value.isEmpty else { return nil }
        return value
    }

    package let deviceIdentity: DeviceIdentity

    package let telemetry: TelemetryClient

    let machine: SessionStateMachine

    private let identity: ConfigIdentity

    /// A process-wide lock, because the installed session is process-wide.
    private static let lock = NSLock()
    private static var installed: PayabliSession?
    private static var testTelemetryTransport: (any TelemetryTransport)?

    /// Written only by the machine of whichever session `install` installed, so it reads `uninitialized` before any.
    static let sink = SdkStateSink()

    static var state: SdkState {
        sink.value
    }

    private static let logger = PayabliLogger(category: .core)

    /// Whether this is still the installed session, a finished one included. A capability built on a session that
    /// was replaced reads false and stops acting for it.
    package var isLive: Bool {
        Self.lock.withLock { Self.installed === self }
    }

    init(
        config: PayabliConfig,
        urlSession: URLSession? = nil,
        deviceIdentity: DeviceIdentity = DeviceIdentity {
            try InstallIdentifier.hardwareId(storage: KeychainStorage(migrating: [InstallIdentifier.storageKey]))
        },
        telemetryTransport: (any TelemetryTransport)? = nil,
        sink: SdkStateSink = SdkStateSink()
    ) {
        self.config = config
        self.deviceIdentity = deviceIdentity
        identity = ConfigIdentity(config)
        let machine = SessionStateMachine(sink: sink)
        self.machine = machine
        let auth = PayabliAuth(config: config)
        self.auth = auth
        let service = PayabliService(
            environment: config.environment,
            readToken: { try await auth.currentAccessToken() },
            client: ClientFacts(
                sdkVersion: PayabliCore.version,
                osVersion: DeviceModel.osVersion(),
                hardware: DeviceModel.hardware(),
                deviceId: { try? deviceIdentity.value() }
            ),
            session: urlSession
        )
        // Handed in at construction, so no request can finish the credential with nothing listening.
        let transport = AuthenticatedTransport(
            base: service,
            auth: auth,
            logger: PayabliLogger(category: .network),
            onUnrecoverable: { _ in machine.markReinitializeRequired() }
        )
        self.transport = transport
        telemetry = TelemetryClient(
            configuration: TelemetryClient.Configuration(
                entry: config.entryPoint,
                environment: config.environment.name
            ),
            transport: telemetryTransport ?? TelemetryEndpointTransport(transport: transport),
            sleep: { try await ContinuousClock().sleep(for: .seconds($0)) },
            lifecycle: UIKitAppLifecycle(),
            deviceId: { try? deviceIdentity.value() },
            queued: [(TelemetryEventName.sdkInitialized, ["state": Self.reportedState])]
        )
    }

    /// The state a report gives for a session that is live and usable, the only one a report is made on.
    private static let reportedState = "ready"

    /// Installs the process's session, or returns it if one is already installed for an equal
    /// configuration.
    ///
    /// Configurations are equal when their entry point and environment are. The token provider is
    /// not compared, so a second call keeps the provider the session started with.
    /// A different configuration throws `invalidConfiguration` and leaves the installed session in
    /// place, because every facade already built is running on it.
    ///
    /// Once the session's credential is finished, after a fresh token was refused too, any configuration
    /// builds a fresh session and installs it in place of the finished one, and its provider is called again.
    /// A `PayabliTTP` built on the finished session refuses from then on; build a new one.
    ///
    /// - Parameter config: the configuration to install; equal by entry point and environment.
    /// - Returns: the process's installed session: the one already installed when it is usable and the configuration
    ///   is equal, or a new one.
    @discardableResult
    public static func initialize(config: PayabliConfig) async throws -> PayabliSession {
        let startedAt = ContinuousClock.now
        do {
            return try install(config: config)
        } catch let refusal as PayabliGenericError {
            await current?.reportRefusedInitialize(refusal, after: ContinuousClock.now - startedAt)
            throw refusal
        } catch {
            // The refusal above takes the errors the SDK classified; this converts what it did not.
            guard let failure = error.payabliUnexpectedFailure else { throw error }
            await current?.reportFailedInitialize(failure, original: error, after: ContinuousClock.now - startedAt)
            throw failure
        }
    }

    /// Reports a refused call as a start and its failure on this session's channel, so the start is answered.
    ///
    /// - Parameter refusal: what the call is about to throw.
    /// - Parameter duration: how long the call took.
    private func reportRefusedInitialize(_ refusal: PayabliGenericError, after duration: Duration) async {
        let (seconds, attoseconds) = duration.components
        let milliseconds = seconds * 1000 + attoseconds / 1_000_000_000_000_000
        await telemetry.emit([
            (TelemetryEventName.sdkInitializeStarted, ["state": Self.reportedState]),
            (TelemetryEventName.sdkInitializeFailed, [
                "outcome": "refused",
                "code": refusal.type.rawValue,
                "error_number": String(refusal.code),
                "reason": refusal.reason,
                "duration_ms": String(milliseconds)
            ])
        ])
    }

    /// Reports an initialize that failed outside the refusals the SDK names, as a start and its
    /// failure on this session's channel, so the start is answered.
    ///
    /// - Parameter failure: what the call is about to throw, converted.
    /// - Parameter original: the error as it was thrown, before conversion, whose type the report names.
    /// - Parameter duration: how long the call took.
    private func reportFailedInitialize(_ failure: PayabliGenericError, original: any Error, after duration: Duration) async {
        let (seconds, attoseconds) = duration.components
        let milliseconds = seconds * 1000 + attoseconds / 1_000_000_000_000_000
        await telemetry.emit([
            (TelemetryEventName.sdkInitializeStarted, ["state": Self.reportedState]),
            (TelemetryEventName.sdkInitializeFailed, [
                "outcome": "failed",
                "code": failure.type.rawValue,
                "error_number": String(failure.code),
                "reason": failure.reason,
                "duration_ms": String(milliseconds),
                "failure_type": String(describing: type(of: original))
            ])
        ])
    }

    static func install(
        config: PayabliConfig,
        urlSession: URLSession? = nil,
        telemetryTransport: (any TelemetryTransport)? = nil
    ) throws -> PayabliSession {
        try lock.withLock {
            let identity = ConfigIdentity(config)
            let current = installed
            // The installed session's own machine: the process-wide state is one value, and a stray write to it must
            // not replace a usable session.
            let live = current.map { !$0.machine.isFinished } ?? false

            if live, let current {
                guard current.identity == identity else {
                    throw PayabliGenericError(
                        type: .invalidConfiguration,
                        reason: "a session is already initialized with a different configuration"
                    )
                }
                return current
            }

            let session = PayabliSession(
                config: config,
                urlSession: urlSession,
                telemetryTransport: telemetryTransport ?? testTelemetryTransport,
                sink: sink
            )
            session.machine.markReady()
            installed = session

            if let current {
                Task { [telemetry = current.telemetry] in await telemetry.stop() }
                logger.warning("session_replaced: replaced a session that required re-initialization")
            } else {
                logger.info("session_initialized")
            }
            return session
        }
    }

    /// Replaces the token a pinned route refused, for a capability to call between the calls of its own sequence.
    ///
    /// - Returns: whether a refused token was waiting; false means nothing was asked of the provider.
    /// - Throws: the provider's failure, as a refresh raises it.
    package func renewRefusedToken() async throws -> Bool {
        try await auth.renewPinnedRefusal()
    }

    /// Whether `config` describes this session, by the same rule `initialize` applies.
    ///
    /// - Parameter config: the configuration to compare this session's against.
    /// - Returns: whether it describes this session, by the same rule `initialize` applies.
    package func matches(_ config: PayabliConfig) -> Bool {
        identity == ConfigIdentity(config)
    }

    /// The installed session, if `initialize` has run.
    package static var current: PayabliSession? {
        lock.withLock { installed }
    }

    /// Drops the installed session and puts the state back, so one test cannot decide the outcome of the next.
    ///
    /// - Parameter telemetryTransport: what later installs report through, so a test reaches no network; nil restores the default.
    static func resetForTesting(telemetryTransport: (any TelemetryTransport)? = nil) {
        lock.withLock {
            installed?.machine.finish()
            installed = nil
            sink.value = .uninitialized
            testTelemetryTransport = telemetryTransport
        }
    }
}

/// The parts of a configuration that decide whether two describe the same session.
///
/// A provider is a closure and has no identity worth comparing: an inline one is new on every call.
private struct ConfigIdentity: Equatable {
    let entryPoint: String
    let environment: PayabliEnvironment

    init(_ config: PayabliConfig) {
        entryPoint = config.entryPoint
        environment = config.environment
    }
}

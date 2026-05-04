import Foundation
import PayabliSDKCore

/// Tap to Pay on iPhone facade.
///
/// Exposes the 9-state session lifecycle, one-call `initialize()` / `charge()`,
/// device activation, pending-update sync, and event stream multicasting.
/// See PRD §19.1.
///
/// ```swift
/// let ttp = PayabliTTP(
///     accessToken: "...", entryPoint: "myEntry",
///     appId: "TEAM.bundle.id", environment: .sandbox
/// )
/// try await ttp.initialize()
/// let result = try await ttp.charge(amount: 9.99, type: .sale)
/// ```
///
/// The façade is split across companion files (same folder, PRD §7.2) to keep
/// each concern focused:
///   - `PayabliTTP+Initialize.swift` — startup & session refresh
///   - `PayabliTTP+Activation.swift` — pending-device activation (PRD §9.7)
///   - `PayabliTTP+Charge.swift`     — 3-step sale pipeline (PRD §19.1)
@MainActor
public final class PayabliTTP: ObservableObject {

    // MARK: - Dependencies

    let entryPoint: String
    let appId: String
    let environment: PayabliEnvironment

    let provider: TapToPayProvider
    let attestation: DeviceAttestationService
    let multicaster = EventMulticaster()
    let retryPolicy: RetryPolicy
    let logger = PayabliLogger(category: .taptopay)

    // Networking
    let service: PayabliService
    let auth: PayabliAuth
    let transactionClient: TTPTransactionClient
    let configClient: TTPConfigClient

    // Deviceid cached from attestation state (used as initiate `device:`).
    var cachedDeviceId: String?

    // Session state
    let sessionManager = SessionManager()

    // MARK: - Published state

    // Setters are `internal` so companion-file extensions
    // (`PayabliTTP+Charge.swift`, etc.) can mutate state without weakening the
    // public read-only contract.
    @Published public internal(set) var sessionState: PayabliTTPSessionState = .idle
    @Published public internal(set) var isReady: Bool = false

    // MARK: - Init

    /// PRD §19.1 convenience init. Wires the default `FiservCardReader`
    /// provider and a real `AppAttestService` with Keychain-backed storage.
    ///
    /// The host supplies the server-minted `accessToken` and an optional
    /// `tokenProvider` callback for refreshes (see `PayabliConfig`).
    ///
    /// Only available where Apple's `DeviceCheck` framework is importable.
    /// The package minimums (iOS 16.7 from PayabliCardReaderCore / ProximityReader,
    /// and macOS 12 from `Package.swift`) are both well above `DCAppAttestService`'s
    /// own floor (iOS 14 / macOS 11.3), so no extra `@available` gate is needed.
    /// Platforms without `DeviceCheck` must use the designated init with a
    /// custom `DeviceAttestationService`.
    #if canImport(DeviceCheck)
    public convenience init(
        accessToken: String,
        tokenProvider: PayabliTokenRefresh? = nil,
        entryPoint: String,
        appId: String,
        environment: PayabliEnvironment
    ) {
        let config = PayabliConfig(
            accessToken: accessToken,
            tokenProvider: tokenProvider,
            entryPoint: entryPoint,
            environment: environment
        )
        let service = PayabliService(environment: environment)
        let auth = PayabliAuth(config: config)
        let storage: SecureStorage = KeychainStorage()
        let attestation = AppAttestService(
            service: service,
            auth: auth,
            attestor: RealAppAttestor(),
            storage: storage
        )
        self.init(
            config: config,
            appId: appId,
            provider: FiservCardReader(),
            attestation: attestation
        )
    }
    #endif

    /// Full-dependency init. Prefer the `accessToken` convenience init for
    /// production; this one is mainly for tests and power users that need to
    /// inject a custom provider or attestation service.
    public init(
        config: PayabliConfig,
        appId: String,
        provider: TapToPayProvider,
        attestation: DeviceAttestationService,
        retryPolicy: RetryPolicy = .default,
        session: URLSession? = nil
    ) {
        self.entryPoint = config.entryPoint
        self.appId = appId
        self.environment = config.environment
        self.provider = provider
        self.attestation = attestation
        self.retryPolicy = retryPolicy

        let service = PayabliService(environment: config.environment, session: session)
        let auth = PayabliAuth(config: config)
        self.service = service
        self.auth = auth
        self.transactionClient = TTPTransactionClient(service: service, auth: auth)
        self.configClient = TTPConfigClient(service: service, auth: auth, attestation: attestation)
    }

    // MARK: - Events

    /// Returns a fresh event stream. Multiple callers each receive all
    /// subsequent events (PRD §19.1 multicasting).
    public nonisolated func events() -> AsyncStream<PayabliTTPEvent> {
        multicaster.stream()
    }

    // MARK: - Shared helpers (extensions)

    /// Re-publishes `sessionState` / `isReady` from `sessionManager`.
    /// Called from every extension after a session transition.
    func syncPublished() {
        sessionState = sessionManager.sessionState
        isReady = sessionManager.isReady
    }
}

import Foundation
import PayabliSDKCore

/// Tap to Pay on iPhone facade.
///
/// Exposes the session lifecycle, one-call `initialize()` / `charge()` and
/// device activation.
///
/// ```swift
/// try await PayabliSession.initialize(config: PayabliConfig(
///     entryPoint: "myEntry",
///     environment: .sandbox,
///     tokenProvider: { try await myBackend.payabliToken() }
/// ))
/// let ttp = try await PayabliTTP.create()
/// try await ttp.initialize()
/// let result = try await ttp.charge(
///     paymentDetails: PayabliTTPPaymentDetails(amount: 9.99)
/// )
/// ```
///
/// The façade is split across companion files (same folder) to keep
/// each concern focused:
///   - `PayabliTTP+Initialize.swift` — startup & session refresh
///   - `PayabliTTP+Activation.swift` — pending-device activation
///   - `PayabliTTP+Charge.swift`     — 3-step sale pipeline
///
/// ## ObjC interop
///
/// `PayabliTTP` inherits `NSObject` so it can be consumed from Objective-C,
/// MAUI/Xamarin (via sharpie-generated bindings), Flutter, and React Native.
/// Each Swift `async throws` method has a callback-based `@objc` companion
/// in the same file — see the `+Initialize`, `+Charge`, and `+Activation`
/// extensions. Swift consumers use the `async throws` API, the published
/// ``sessionState`` and value-type `struct`s. See `README.md` for the
/// bilingual contract.
@available(iOS 16.7, *)
@objc(PayabliTTP)
@MainActor
public final class PayabliTTP: NSObject, ObservableObject {
    // MARK: - Dependencies

    let entryPoint: String
    let environment: PayabliEnvironment

    let provider: TapToPayProvider
    let attestation: DeviceAttestationService
    let retryPolicy: RetryPolicy
    let logger = PayabliLogger(category: .taptopay)

    /// Networking
    let session: PayabliSession

    let isLive: @Sendable () -> Bool
    let reports: TapToPayReports
    let transactionClient: TTPTransactionClient
    let chargeKeys: ChargeKeyStore
    let configClient: TTPConfigClient

    let sessionManager = SessionManager()

    /// The configuration currently running, or `nil` when none is. A reader's event handler outlives the
    /// configuration that installed it, so progress is recorded only while its own configuration is this one,
    /// including after a configuration that failed, which the gate's reader generation would still match.
    var activeConfiguration: Int?

    /// The configuration whose reader came up last, or `nil` before one has. A
    /// prompt from any other reader is dropped.
    var preparedReader: Int?

    /// Names each configuration, so an ended one can be told from a new one.
    var nextConfigurationID = 0

    /// Told every time ``sessionState`` changes.
    private var sessionStateObservations: [TapToPaySessionStateObservation] = []

    // MARK: - Published state

    // Setters are `internal` so companion-file extensions
    // (`PayabliTTP+Charge.swift`, etc.) can mutate state without weakening the
    // public read-only contract.
    @Published public internal(set) var sessionState: PayabliTTPSessionState = .idle
    @Published public internal(set) var isReady: Bool = false

    // MARK: - ObjC projection

    /// ``sessionState`` without its payload, for a host that cannot express an
    /// enum carrying one.
    @objc public var sessionStateCode: PayabliTTPSessionStateCode {
        sessionState.code
    }

    /// How far the reader has got configuring, or `nil` when no configuration
    /// is running. `NSNumber` because ObjC has no optional `Int`.
    @objc public var readerConfigurationPercent: NSNumber? {
        sessionState.readerConfigurationPercent.map(NSNumber.init(value:))
    }

    /// What the running charge is doing, as a ``TapToPayChargeActivity`` raw
    /// value, or `nil` when no charge is running.
    @objc public var chargeActivity: NSNumber? {
        sessionState.chargeActivity.map { NSNumber(value: $0.rawValue) }
    }

    /// Why the session failed, or `nil` when it has not.
    @objc public var failureReason: NSNumber? {
        sessionState.failureReason.map { NSNumber(value: $0.rawValue) }
    }

    /// The id the device is activated under, or `nil` when no activation is owed.
    @objc public var activationId: String? {
        sessionState.activationId
    }

    // MARK: - Init

    /// `package`: it takes the provider and the attestation service, so a host reaching
    /// it could substitute either. A host uses `create()` below instead.
    ///
    /// - Parameters:
    ///   - session: the session whose entry point, environment and transport the facade runs on.
    ///   - provider: the card reader the charges read through.
    ///   - attestation: the service that holds the device's binding and signs requests.
    ///   - retryPolicy: the retry policy the charge's update runs under.
    ///   - isLive: whether `session` is still the installed one; this terminal stops arming the reader once it is not.
    ///   - chargeKeys: the idempotency keys of unsettled charges, shared by every terminal in the process.
    package init(
        session: PayabliSession,
        provider: TapToPayProvider,
        attestation: DeviceAttestationService,
        retryPolicy: RetryPolicy = .default,
        isLive: (@Sendable () -> Bool)? = nil,
        chargeKeys: ChargeKeyStore = .process
    ) {
        self.isLive = isLive ?? { session.isLive }
        self.entryPoint = session.config.entryPoint
        self.environment = session.config.environment
        self.provider = provider
        self.attestation = attestation
        self.retryPolicy = retryPolicy

        self.session = session
        self.reports = TapToPayReports(telemetry: session.telemetry)
        self.transactionClient = TTPTransactionClient(transport: session.transport)
        self.chargeKeys = chargeKeys
        self.configClient = TTPConfigClient(
            transport: session.transport,
            attestation: attestation
        )
        super.init()
    }

    #if canImport(DeviceCheck)
        /// Builds the card-present facade on the session `PayabliSession.initialize(config:)`
        /// installed, with the default card reader and App Attest backed by the Keychain.
        ///
        /// Throws `sessionNotInitialized` when no session is installed.
        ///
        /// - Returns: the card-present facade, built on the installed session.
        @objc public static func create() async throws -> PayabliTTP {
            guard let payabliSession = PayabliSession.current else {
                throw TapToPayError(type: .sessionNotInitialized, reason: "no session is initialized", detail: nil)
            }
            let attestation = AppAttestService(
                transport: payabliSession.transport,
                attestor: RealAppAttestor(),
                storage: KeychainStorage(migrating: PayabliKeychainKey.all),
                deviceIdentity: payabliSession.deviceIdentity
            )
            return PayabliTTP(
                session: payabliSession,
                provider: FiservCardReader(),
                attestation: attestation
            )
        }
    #endif

    // MARK: - Shared helpers (extensions)

    /// Re-publishes `sessionState` / `isReady` from `sessionManager`.
    /// Called from every extension after a session transition.
    func syncPublished() {
        if isReady != sessionManager.isReady {
            isReady = sessionManager.isReady
        }
        guard sessionState != sessionManager.sessionState else { return }
        sessionState = sessionManager.sessionState
        sessionStateObservations.removeAll { $0.isCancelled }
        for observation in sessionStateObservations {
            observation.notify()
        }
    }

    // MARK: - ObjC state observation

    /// Calls `handler` on the main thread after every change to ``sessionState``,
    /// including a move from one ``TapToPayChargeActivity`` to another. The
    /// handler carries nothing: it reads ``sessionStateCode`` and the payload
    /// accessors, which already hold the new state when it runs.
    ///
    /// Observing lasts until ``TapToPaySessionStateObservation/cancel()`` or for
    /// the lifetime of this instance.
    ///
    /// - Parameter handler: the callback to run after every change to ``sessionState``.
    /// - Returns: the observation to cancel it with, lasting otherwise for this instance's lifetime.
    @objc public func addSessionStateObserver(
        _ handler: @escaping () -> Void
    ) -> TapToPaySessionStateObservation {
        let observation = TapToPaySessionStateObservation(handler: handler)
        sessionStateObservations.removeAll { $0.isCancelled }
        sessionStateObservations.append(observation)
        return observation
    }
}

// MARK: - ObjC state observation handle

/// Returned by ``PayabliTTP/addSessionStateObserver(_:)``.
@objc(TapToPaySessionStateObservation)
public final class TapToPaySessionStateObservation: NSObject, @unchecked Sendable {
    /// Recursive, and held while the handler runs: `cancel()` returns only once no call is in progress,
    /// and a handler may cancel its own observation.
    private let lock = NSRecursiveLock()
    private var handler: (() -> Void)?

    init(handler: @escaping () -> Void) {
        self.handler = handler
        super.init()
    }

    /// Stops the handler being called. Safe from any thread, and idempotent.
    @objc public func cancel() {
        lock.lock()
        handler = nil
        lock.unlock()
    }

    var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return handler == nil
    }

    func notify() {
        lock.lock()
        defer { lock.unlock() }
        handler?()
    }
}

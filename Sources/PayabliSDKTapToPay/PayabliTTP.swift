import Foundation
import PayabliSDKCore

/// Tap to Pay on iPhone facade.
///
/// Exposes the session lifecycle, one-call `initialize()` / `charge()`,
/// device activation, pending-update sync, and event stream multicasting.
/// See PRD §19.1.
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
///     type: .sale,
///     paymentDetails: PayabliTTPPaymentDetails(amount: 9.99)
/// )
/// ```
///
/// The façade is split across companion files (same folder, PRD §7.2) to keep
/// each concern focused:
///   - `PayabliTTP+Initialize.swift` — startup & session refresh
///   - `PayabliTTP+Activation.swift` — pending-device activation (PRD §9.7)
///   - `PayabliTTP+Charge.swift`     — 3-step sale pipeline (PRD §19.1)
///
/// ## ObjC interop
///
/// `PayabliTTP` inherits `NSObject` so it can be consumed from Objective-C,
/// MAUI/Xamarin (via sharpie-generated bindings), Flutter, and React Native.
/// Each Swift `async throws` method has a callback-based `@objc` companion
/// in the same file — see the `+Initialize`, `+Charge`, and `+Activation`
/// extensions. Existing Swift consumers continue to use the unchanged
/// `async throws` API, `AsyncStream<PayabliTTPEvent>` events, and value-type
/// `struct`s. See `README.md` for the bilingual contract.
@objc(PayabliTTP)
@MainActor
public final class PayabliTTP: NSObject, ObservableObject {
    // MARK: - Dependencies

    let entryPoint: String
    let environment: PayabliEnvironment

    let provider: TapToPayProvider
    let attestation: DeviceAttestationService
    let multicaster = TTPEventMulticaster()
    let retryPolicy: RetryPolicy
    let logger = PayabliLogger(category: .taptopay)

    // Networking
    let session: PayabliSession
    let transactionClient: TTPTransactionClient
    let configClient: TTPConfigClient

    /// Session state
    let sessionManager = SessionManager()

    /// Bumped every time a reader is prepared. A charge captures it before the
    /// tap so a failure that arrives after the reader was replaced is not
    /// attributed to the replacement.
    var readerSessionGeneration = 0

    /// The configuration currently running, or `nil` when none is. A reader's
    /// event handler outlives the configuration that installed it, so progress
    /// is announced only while its own configuration is still this one.
    ///
    /// Separate from `readerSessionGeneration`, which bumps only when a reader
    /// comes up: a percentage raised after a configuration failed would still
    /// match that.
    var activeConfiguration: Int?

    /// Names each configuration, so an ended one can be told from a new one.
    var nextConfigurationID = 0

    /// The session setup in progress, if any, and which entry point started it.
    /// A caller of the same kind joins it, the way `PayabliAuth` deduplicates a
    /// token refresh; a caller of the other kind waits for it to finish.
    var inFlightSessionSetup: (kind: SessionSetupKind, task: Task<Void, Error>, id: Int)?

    /// Identifies a setup so it only clears the slot while it is still the
    /// current one.
    var nextSessionSetupID = 0

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

    /// Why the session failed, or `nil` when it has not.
    @objc public var failureReason: NSNumber? {
        sessionState.failureReason.map { NSNumber(value: $0.rawValue) }
    }

    // MARK: - Init

    /// `package`: it takes the provider and the attestation service, so a host reaching
    /// it could substitute either. A host uses `create()` below instead.
    package init(
        session: PayabliSession,
        provider: TapToPayProvider,
        attestation: DeviceAttestationService,
        retryPolicy: RetryPolicy = .default
    ) {
        self.entryPoint = session.config.entryPoint
        self.environment = session.config.environment
        self.provider = provider
        self.attestation = attestation
        self.retryPolicy = retryPolicy

        self.session = session
        self.transactionClient = TTPTransactionClient(transport: session.transport)
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
        /// Throws `notInitialized` when no session is installed.
        @objc public static func create() async throws -> PayabliTTP {
            guard let payabliSession = PayabliSession.current else {
                throw PayabliTTPError.notInitialized
            }
            let attestation = AppAttestService(
                transport: payabliSession.transport,
                attestor: RealAppAttestor(),
                storage: KeychainStorage()
            )
            return PayabliTTP(
                session: payabliSession,
                provider: FiservCardReader(),
                attestation: attestation
            )
        }
    #endif

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

    // MARK: - ObjC event listener

    /// Subscribes a callback to the `events()` stream — the ObjC / MAUI
    /// counterpart to iterating `for await event in ttp.events()` in Swift.
    ///
    /// The handler is invoked on the main thread (the entire `PayabliTTP`
    /// surface is `@MainActor`). Each event is delivered as a
    /// `(PayabliTTPEventCode, NSDictionary)` pair: `code` identifies the
    /// case, and the dictionary carries the case's associated values
    /// (`paymentTransId`, `error`) — empty for cases without payload. See
    /// `PayabliTTPEvent.payload` for the per-case schema.
    ///
    /// The returned `PayabliTTPEventToken` owns the underlying `Task`. Call
    /// `cancel()` to stop receiving events; otherwise the listener lives
    /// for the lifetime of the `PayabliTTP` instance.
    @objc public func addEventListener(
        handler: @escaping (PayabliTTPEventCode, NSDictionary) -> Void
    ) -> PayabliTTPEventToken {
        let stream = self.events()
        let task = Task { @MainActor in
            for await event in stream {
                handler(event.code, event.payload as NSDictionary)
            }
        }
        return PayabliTTPEventToken(task: task)
    }
}

// MARK: - ObjC event token

/// Opaque handle returned by `PayabliTTP.addEventListener(handler:)`. Holds
/// the underlying `Task` that drains the `AsyncStream<PayabliTTPEvent>` and
/// dispatches to the ObjC callback. Call `cancel()` to tear it down.
@objc(PayabliTTPEventToken)
public final class PayabliTTPEventToken: NSObject {
    let task: Task<Void, Never>

    init(task: Task<Void, Never>) {
        self.task = task
        super.init()
    }

    /// Cancels the underlying task. Idempotent.
    @objc public func cancel() {
        task.cancel()
    }
}

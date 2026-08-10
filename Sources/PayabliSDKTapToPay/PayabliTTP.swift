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
    let appId: String
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

    // Deviceid cached from attestation state (used as initiate `device:`).
    var cachedDeviceId: String?

    // Session state
    let sessionManager = SessionManager()

    /// Bumped every time a reader is prepared. A charge captures it before the
    /// tap so a failure that arrives after the reader was replaced is not
    /// attributed to the replacement.
    var readerSessionGeneration = 0

    /// The initialization in progress, if any. A second caller joins it instead
    /// of starting a competing one, the way `PayabliAuth` deduplicates a token
    /// refresh.
    var inFlightInitialize: Task<Void, Error>?

    // MARK: - Published state

    // Setters are `internal` so companion-file extensions
    // (`PayabliTTP+Charge.swift`, etc.) can mutate state without weakening the
    // public read-only contract.
    @Published public internal(set) var sessionState: PayabliTTPSessionState = .idle
    @Published public internal(set) var isReady: Bool = false

    // MARK: - Init

    /// Designated init. Shares a single `PayabliAuth` + `PayabliService`
    /// across every component facade constructed with the same `PayabliSession`.
    public init(
        session: PayabliSession,
        appId: String,
        provider: TapToPayProvider,
        attestation: DeviceAttestationService,
        retryPolicy: RetryPolicy = .default
    ) {
        self.entryPoint = session.config.entryPoint
        self.appId = appId
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

    /// Convenience init that wraps a `PayabliConfig` in a fresh
    /// `PayabliSession`. Use the `session:` init when you need to share auth
    /// across multiple component facades on the same config.
    public convenience init(
        config: PayabliConfig,
        appId: String,
        provider: TapToPayProvider,
        attestation: DeviceAttestationService,
        retryPolicy: RetryPolicy = .default,
        session: URLSession? = nil
    ) {
        let payabliSession = PayabliSession(config: config, urlSession: session)
        self.init(
            session: payabliSession,
            appId: appId,
            provider: provider,
            attestation: attestation,
            retryPolicy: retryPolicy
        )
    }

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
        let payabliSession = PayabliSession(config: config)
        let storage: SecureStorage = KeychainStorage()
        let attestation = AppAttestService(
            transport: payabliSession.transport,
            attestor: RealAppAttestor(),
            storage: storage
        )
        self.init(
            session: payabliSession,
            appId: appId,
            provider: FiservCardReader(),
            attestation: attestation
        )
    }
    #endif

    /// `@objc`-friendly convenience init for ObjC / MAUI / sharpie consumers
    /// that can't represent the Swift `PayabliTokenRefresh` (`@Sendable () async
    /// throws -> String`) closure.
    ///
    /// Token refresh is exposed here as a completion-style block:
    /// `tokenRefreshHandler` receives a `(token, error) -> Void` callback that
    /// the host invokes exactly once with either a fresh access token or an
    /// `NSError` — the SDK bridges that to the underlying async closure
    /// internally. Pass `nil` to disable silent refresh; the SDK will surface
    /// `tokenExpired` instead.
    ///
    /// All other parameters mirror the Swift convenience init exactly. Swift
    /// callers that need an `async throws` token provider should keep using
    /// the Swift-only convenience init above.
    #if canImport(DeviceCheck)
    @objc public convenience init(
        accessToken: String,
        tokenRefreshHandler: ((@escaping (String?, NSError?) -> Void) -> Void)?,
        entryPoint: String,
        appId: String,
        environment: PayabliEnvironment
    ) {
        let bridged: PayabliTokenRefresh? = tokenRefreshHandler.map { handler in
            // ObjC blocks are heap-allocated and copy-on-capture, so the
            // bridged closure can safely be `@Sendable` even though Swift
            // does not infer `@Sendable` for the input handler type.
            let sendable = UncheckedSendableBox(handler)
            return { @Sendable in
                try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
                    // Guard against the ObjC host invoking the completion
                    // block more than once — that would resume the same
                    // continuation twice and crash. We honor only the first
                    // invocation (success or failure) and silently drop any
                    // subsequent calls. A `Locked<Bool>` keeps this thread-
                    // safe in case the host dispatches the callback from a
                    // background queue.
                    let resumed = Locked(false)
                    sendable.value { token, error in
                        let firstCall = resumed.withLock { hasResumed in
                            guard !hasResumed else { return false }
                            hasResumed = true
                            return true
                        }
                        guard firstCall else { return }
                        if let error {
                            continuation.resume(throwing: error)
                        } else if let token {
                            continuation.resume(returning: token)
                        } else {
                            continuation.resume(throwing: NSError(
                                domain: "com.payabli.ttp",
                                code: -1,
                                userInfo: [NSLocalizedDescriptionKey:
                                    "tokenRefreshHandler returned nil token and nil error"]
                            ))
                        }
                    }
                }
            }
        }
        self.init(
            accessToken: accessToken,
            tokenProvider: bridged,
            entryPoint: entryPoint,
            appId: appId,
            environment: environment
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

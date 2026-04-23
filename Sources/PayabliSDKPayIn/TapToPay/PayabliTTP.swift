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
///     clientId: "...", clientSecret: "...",
///     entry: "myEntry", appId: "TEAM.bundle.id",
///     environment: .sandbox,
///     provider: FiservCardReader(),
///     attestation: RealDeviceAttestationService()
/// )
/// try await ttp.initialize()
/// let result = try await ttp.charge(amount: 9.99, type: .sale)
/// ```
@MainActor
public final class PayabliTTP: ObservableObject {

    // MARK: - Dependencies

    private let entry: String
    private let appId: String
    private let environment: PayabliEnvironment

    private let provider: TapToPayProvider
    private let attestation: DeviceAttestationService
    private let queue: PendingUpdateQueue
    private let multicaster = EventMulticaster()
    private let retryPolicy: RetryPolicy
    private let logger = PayabliLogger(category: .taptopay)

    // Networking
    private let service: PayabliService
    private let auth: PayabliAuth
    private let transactionClient: TTPTransactionClient
    private let configClient: TTPConfigClient

    // Deviceid cached from attestation state (used as initiate `device:`).
    private var cachedDeviceId: String?

    // Session state
    private let sessionManager = SessionManager()

    // MARK: - Published state

    @Published public private(set) var sessionState: PayabliTTPSessionState = .idle
    @Published public private(set) var isReady: Bool = false
    @Published public private(set) var pendingUpdates: [PendingUpdate] = []

    // MARK: - Init

    /// Full-dependency init. Prefer `init(config:appId:provider:attestation:)`
    /// for production — this one is mainly for tests and power users.
    /// PRD §19.1 style convenience init. Wires the default `FiservCardReader`
    /// provider and a real `AppAttestService` with Keychain-backed storage.
    ///
    /// The host supplies the server-minted `accessToken` and an optional
    /// `tokenProvider` callback for refreshes (see `PayabliConfig`).
    public convenience init(
        accessToken: String,
        tokenProvider: PayabliTokenRefresh? = nil,
        entry: String,
        appId: String,
        environment: PayabliEnvironment
    ) {
        #if canImport(DeviceCheck)
        if #available(iOS 14.0, macOS 11.3, *) {
            let config = PayabliConfig(
                accessToken: accessToken,
                tokenProvider: tokenProvider,
                entryPoint: entry,
                environment: environment
            )
            let service = PayabliService(environment: environment)
            let auth = PayabliAuth(config: config)
            let storage: SecureStorage = KeychainStorage()
            let attestation = AppAttestService(
                service: service,
                auth: auth,
                attestor: RealAppAttestor(),
                storage: storage,
                entry: entry,
                appId: appId
            )
            self.init(
                config: config,
                appId: appId,
                provider: FiservCardReader(),
                attestation: attestation
            )
            return
        }
        #endif

        // Fallback for environments without DeviceCheck — never used on a
        // Tap-to-Pay-capable device, but keeps the init signature callable in
        // test builds on macOS.
        self.init(
            config: PayabliConfig(
                accessToken: accessToken,
                tokenProvider: tokenProvider,
                entryPoint: entry,
                environment: environment
            ),
            appId: appId,
            provider: FiservCardReader(),
            attestation: NoopAttestationService()
        )
    }

    public init(
        config: PayabliConfig,
        appId: String,
        provider: TapToPayProvider,
        attestation: DeviceAttestationService,
        queue: PendingUpdateQueue = PendingUpdateQueue(),
        retryPolicy: RetryPolicy = .default,
        session: URLSession? = nil
    ) {
        self.entry = config.entryPoint
        self.appId = appId
        self.environment = config.environment
        self.provider = provider
        self.attestation = attestation
        self.queue = queue
        self.retryPolicy = retryPolicy

        let service = PayabliService(environment: config.environment, session: session)
        let auth = PayabliAuth(config: config)
        self.service = service
        self.auth = auth
        self.transactionClient = TTPTransactionClient(service: service, auth: auth)
        self.configClient = TTPConfigClient(service: service, auth: auth, attestation: attestation)

        self.pendingUpdates = queue.load()
    }

    // MARK: - Public API (PRD §19.1)

    /// One-call startup: attestation (first run) / warm start → fetch config →
    /// prepare reader → `.ready`.
    public func initialize() async throws {
        // Eligibility gate — bail before touching network / UI (PRD FR-11J.2).
        if case .failure(let err) = await provider.checkEligibility() {
            sessionManager.markError(err)
            syncPublished()
            throw err
        }

        var resolvedDeviceId: String?

        if attestation.isAlreadyAttested {
            // Warm path: deviceId was persisted by a previous successful
            // attestation. We still need it to call /initiate later.
            resolvedDeviceId = attestation.cachedDeviceId
            _ = sessionManager.transition(to: .fetchingConfig)
        } else {
            _ = sessionManager.transition(to: .attestingDevice)
            multicaster.emit(.attestationStarted)
            do {
                let result = try await attestation.attest(entry: entry, appId: appId)
                resolvedDeviceId = result.deviceId
                multicaster.emit(.attestationCompleted)
            } catch PayabliTTPError.devicePendingActivation {
                _ = sessionManager.transition(to: .pendingActivation)
                syncPublished()
                multicaster.emit(.devicePendingActivation)
                throw PayabliTTPError.devicePendingActivation
            } catch {
                sessionManager.markError(error)
                syncPublished()
                throw error
            }
            _ = sessionManager.transition(to: .fetchingConfig)
        }
        syncPublished()

        // GET /config/{entry} — gated by App Attest assertion headers.
        // 401 here means the assertion was rejected (possibly stale key);
        // clear attestation and bubble up for the caller to re-initialize.
        let config: TTPConfig
        do {
            config = try await configClient.fetchConfig(entry: entry)
        } catch PayabliTTPError.devicePendingActivation {
            // Warm path: keyId/deviceId were already in keychain so we skipped
            // attestation, but the backend says the device is still pending
            // (e.g. first `/activate` never completed). Surface the same
            // `.pendingActivation` state as the cold path so the caller can
            // drive the activation UI and we remain eligible for
            // `activateDevice(...)`.
            _ = sessionManager.transition(to: .pendingActivation)
            syncPublished()
            multicaster.emit(.devicePendingActivation)
            throw PayabliTTPError.devicePendingActivation
        } catch let err as PayabliGenericError where err.code == .tokenExpired {
            attestation.clearCache()
            sessionManager.markError(err)
            syncPublished()
            throw PayabliTTPError.configFailed(reason: "Config rejected (401) — attestation cleared")
        } catch {
            sessionManager.markError(error)
            syncPublished()
            throw error is PayabliTTPError
                ? (error as! PayabliTTPError)
                : PayabliTTPError.configFailed(reason: String(describing: error))
        }
        multicaster.emit(.configReceived)
        cachedDeviceId = resolvedDeviceId

        // Hand the opaque credentials block to the provider — it knows how to
        // validate and consume its own keys. Provider-specific parsing never
        // leaks into the facade.
        do {
            try provider.configure(credentials: config.providerCredentials)
        } catch {
            sessionManager.markError(error)
            syncPublished()
            throw error is PayabliTTPError
                ? (error as! PayabliTTPError)
                : PayabliTTPError.readerSetupFailed(reason: String(describing: error))
        }

        _ = sessionManager.transition(to: .initializingReader)
        syncPublished()
        multicaster.emit(.readerInitializing)
        do {
            try await provider.prepareReader()
        } catch {
            sessionManager.markError(error)
            syncPublished()
            throw PayabliTTPError.readerSetupFailed(reason: String(describing: error))
        }
        _ = sessionManager.transition(to: .ready)
        syncPublished()
        multicaster.emit(.readerReady)

        // Best-effort flush of any queue entries (PRD FR-11C.4).
        Task { [weak self] in
            try? await self?.syncTransactions()
        }
    }

    /// Requests (or returns the currently-valid) activation code for a device
    /// that is `pendingActivation`. Hits
    /// `POST /api/v2/device/taptopay/activate/challenge`. In production this
    /// is typically called from an admin dashboard; exposed here so test/POC
    /// hosts can drive the entire activation flow from the device itself.
    public func requestActivationCode() async throws -> ActivationCodeInfo {
        guard sessionState == .pendingActivation else {
            throw PayabliTTPError.invalidState(
                current: sessionState,
                attempted: "requestActivationCode"
            )
        }
        return try await attestation.requestActivationCode(entry: entry)
    }

    /// Activate a pending device using an admin-supplied code (PRD §9.7).
    public func activateDevice(activationCode: String) async throws {
        guard sessionState == .pendingActivation else {
            throw PayabliTTPError.invalidState(
                current: sessionState,
                attempted: "activateDevice"
            )
        }
        do {
            try await attestation.activateDevice(activationCode: activationCode, entry: entry)
            _ = sessionManager.transition(to: .idle)
            syncPublished()
        } catch let err as PayabliTTPError {
            // The attestation service already cleared local cache for the
            // revoked case. Reset the session to `.idle` (not `.error`) so
            // the caller can immediately re-run `initialize()` which will
            // perform a fresh cold-path attestation.
            if case .attestationRevoked = err {
                _ = sessionManager.transition(to: .idle)
                syncPublished()
                multicaster.emit(.sessionExpired)
                throw err
            }
            sessionManager.markError(err)
            syncPublished()
            throw err
        } catch {
            sessionManager.markError(error)
            syncPublished()
            throw PayabliTTPError.activationFailed(reason: String(describing: error))
        }
    }

    /// Charge a transaction. v1.0 supports `.sale` only (PRD FR-11D.1).
    ///
    /// Implements the same 3-step flow used by the Fiserv reference POC
    /// (`SaleView.processSale`) — and threads the provided `customer` / `order`
    /// snapshot transparently through every stage so partners only supply it
    /// once:
    ///
    ///   1. `POST /api/v2/MoneyIn/initiate` — `customer.*` lands in the
    ///      backend `customerData` block, `order.*` in `orderId` /
    ///      `orderDescription`. Payabli mints the authoritative `paymentTransId`
    ///      (the SDK never synthesises one).
    ///   2. Provider `startReading(_:)` — the same `customer` / `order` values
    ///      reach the adapter via `CardReadRequest`. `paymentTransId` is wired
    ///      as both `merchantTransactionId` and `merchantOrderId` so the
    ///      CommerceHub response stitches back to the same Payabli record;
    ///      `order.invoiceNumber ?? order.orderId` becomes
    ///      `merchantInvoiceNumber`.
    ///   3. `PATCH /api/v2/MoneyIn/update/{paymentTransId}` — backend looks up
    ///      the transaction by id and reuses the customer/order persisted at
    ///      step 1, so the update body only carries the provider response.
    ///
    /// - Parameters:
    ///   - amount: Total amount to charge (includes `serviceFee`).
    ///   - type: Payment type (only `.sale` is supported in v1.0).
    ///   - serviceFee: Optional service fee portion of `amount`.
    ///   - customer: Structured customer data. Defaults to an empty snapshot
    ///     for anonymous payors.
    ///   - order: Structured order / invoice data. Defaults to an empty
    ///     snapshot.
    public func charge(
        amount: Decimal,
        type: PayabliTTPPaymentType,
        serviceFee: Decimal = 0,
        customer: PayabliTTPCustomerData = PayabliTTPCustomerData(),
        order: PayabliTTPOrderData = PayabliTTPOrderData()
    ) async throws -> TransactionResult {
        guard type == .sale else {
            throw PayabliTTPError.invalidState(current: sessionState, attempted: "charge(non-sale)")
        }

        try await reinitializeIfNeeded()

        guard sessionState == .ready else {
            throw PayabliTTPError.notReady(current: sessionState)
        }

        let context = TTPTransactionContext(
            amount: amount,
            serviceFee: serviceFee,
            customer: customer,
            order: order
        )

        logger.info(
            "[charge] → amount=\(context.amount) serviceFee=\(context.serviceFee) " +
            "customer={firstName=\(customer.firstName ?? "<nil>") " +
            "lastName=\(customer.lastName ?? "<nil>") " +
            "customerNumber=\(customer.customerNumber ?? "<nil>")} " +
            "order={orderId=\(order.orderId ?? "<nil>") " +
            "description=\(order.orderDescription ?? "<nil>") " +
            "invoice=\(order.invoiceNumber ?? "<nil>")}"
        )

        // Step 1 — /MoneyIn/initiate: the backend mints the paymentTransId.
        let paymentTransId = try await runInitiate(context: context)
        multicaster.emit(.chargeInitiated(paymentTransId: paymentTransId))

        // Step 2 — NFC tap. paymentTransId is wired as both merchantTransactionId
        // and merchantOrderId (matching the reference flow). Customer and
        // order snapshots flow through so adapters (and their logs) always see
        // the same data that was persisted at /initiate.
        multicaster.emit(.nfcStarted)
        let readResult: CardReadResult
        let invoiceNumber = context.order.invoiceNumber ?? context.order.orderId
        let readRequest = CardReadRequest(
            amount: context.amount,
            merchantTransactionId: paymentTransId,
            merchantOrderId: paymentTransId,
            merchantInvoiceNumber: invoiceNumber,
            customer: context.customer,
            order: context.order
        )
        do {
            readResult = try await provider.startReading(readRequest)
            multicaster.emit(.nfcCompleted)
        } catch {
            multicaster.emit(.nfcFailed(error: String(describing: error)))

            // Try error-update PATCH with retry; enqueue on exhaustion.
            let errorBody = makeErrorUpdateBody(error: error)
            let synced = await tryUpdate(
                paymentTransId: paymentTransId,
                body: errorBody
            )
            if !synced {
                queue.enqueue(PendingUpdate(paymentTransId: paymentTransId, updateBody: errorBody))
                pendingUpdates = queue.load()
                multicaster.emit(.pendingUpdateEnqueued(paymentTransId: paymentTransId))
            }
            throw PayabliTTPError.nfcFailed(reason: String(describing: error))
        }

        // Success update PATCH
        let updateBody = makeSuccessUpdateBody(result: readResult)
        let synced = await tryUpdate(
            paymentTransId: paymentTransId,
            body: updateBody
        )
        if synced {
            multicaster.emit(.updateCompleted(paymentTransId: paymentTransId))
            return TransactionResult(paymentTransId: paymentTransId, syncStatus: .synced)
        } else {
            queue.enqueue(PendingUpdate(paymentTransId: paymentTransId, updateBody: updateBody))
            pendingUpdates = queue.load()
            multicaster.emit(.pendingUpdateEnqueued(paymentTransId: paymentTransId))
            return TransactionResult(
                paymentTransId: paymentTransId,
                syncStatus: .pendingSyncWithBackend
            )
        }
    }

    /// Flush pending updates to the backend (PRD FR-11E.3).
    public func syncTransactions() async throws {
        let current = queue.evictExpired()
        pendingUpdates = current
        if current.isEmpty { return }

        try await reinitializeIfNeeded()

        for entry in current {
            let synced = await tryUpdate(paymentTransId: entry.paymentTransId, body: entry.updateBody)
            if synced {
                queue.remove(paymentTransId: entry.paymentTransId)
                multicaster.emit(.pendingUpdateSynced(paymentTransId: entry.paymentTransId))
            }
        }
        pendingUpdates = queue.load()
    }

    /// Returns a fresh event stream. Multiple callers receive all subsequent events.
    public nonisolated func events() -> AsyncStream<PayabliTTPEvent> {
        multicaster.stream()
    }

    // MARK: - Session refresh (host / Flutter bridge)

    public func reinitializeIfNeeded() async throws {
        switch sessionState {
        case .ready:
            return
        case .sessionExpired, .idle, .error:
            multicaster.emit(.reinitializeStarted)
            _ = sessionManager.transition(to: .reinitializing)
            syncPublished()
            _ = sessionManager.transition(to: .fetchingConfig)
            syncPublished()
            _ = sessionManager.transition(to: .initializingReader)
            syncPublished()
            do {
                try await provider.prepareReader()
            } catch {
                sessionManager.markError(error)
                syncPublished()
                throw error
            }
            _ = sessionManager.transition(to: .ready)
            syncPublished()
            multicaster.emit(.reinitializeCompleted)
        default:
            throw PayabliTTPError.notReady(current: sessionState)
        }
    }

    /// Invokes `POST /api/v2/MoneyIn/initiate` using the real client. The
    /// backend returns the authoritative `paymentTransId` — the SDK never
    /// synthesizes one. If `deviceId` hasn't been resolved yet (either from a
    /// fresh attestation or from the keychain), we fail loudly instead of
    /// making up an ID, because any subsequent `PATCH /update/{id}` would
    /// 400 against a non-existent transaction.
    private func runInitiate(context: TTPTransactionContext) async throws -> String {
        guard let deviceId = cachedDeviceId else {
            throw PayabliTTPError.initiateFailed(
                reason: "Missing deviceId — run initialize() before charge()"
            )
        }
        return try await transactionClient.initiate(
            entryPoint: entry,
            amount: context.amount,
            serviceFee: context.serviceFee,
            deviceId: deviceId,
            customer: context.customer,
            order: context.order
        )
    }

    private func makeSuccessUpdateBody(result: CardReadResult) -> Data {
        // Atomic providers (Fiserv) already return the full CommerceHub response —
        // forward it verbatim under `fiservResponse` so the backend receives the
        // exact dict shape the processor produced. For payload-only providers we
        // fall back to wrapping the `CardReadResult` fields ourselves.
        if let json = result.providerResponseJSON,
           let dict = (try? JSONSerialization.jsonObject(with: json)) as? [String: Any] {
            return TTPTransactionClient.successUpdateBody(providerResponse: dict)
        }
        return TTPTransactionClient.successUpdateBody(providerResponse: [
            "provider": result.provider,
            "encryptedPayload": result.encryptedPayload.base64EncodedString(),
            "cardNetwork": result.cardNetwork as Any,
            "providerMetadata": result.providerMetadata
        ])
    }


    private func makeErrorUpdateBody(error: Error) -> Data {
        TTPTransactionClient.errorUpdateBody(
            description: String(describing: error)
        )
    }

    /// Attempt `PATCH /update/{paymentTransId}` with retry. Returns `true` on
    /// success, `false` when retries are exhausted. Non-retryable errors
    /// propagate via `false` (enqueue path).
    ///
    /// 401 on PATCH triggers a token refresh via `auth.invalidateAndRefresh()`
    /// and one retry (FR-11D.5).
    private func tryUpdate(paymentTransId: String, body: Data) async -> Bool {
        let logger = self.logger
        let bodyDump = String(data: body, encoding: .utf8) ?? "<non-utf8 \(body.count) bytes>"
        let path = "/api/v2/MoneyIn/update/\(paymentTransId)"

        @Sendable func performOnce(token: String, attempt: String) async throws -> PayabliResponse {
            let request = PayabliRequest(
                method: .patch,
                path: path,
                headers: [
                    "Authorization": "Bearer \(token)",
                    "Content-Type": "application/json"
                ],
                body: body
            )
            let headersDump = request.headers
                .map { "\($0.key): \($0.value)" }
                .sorted()
                .joined(separator: " | ")
            logger.info("[update/\(attempt)] → PATCH \(path)")
            logger.info("[update/\(attempt)] headers: \(headersDump)")
            logger.info("[update/\(attempt)] body: \(bodyDump)")
            let response = try await service.perform(request)
            let responseBody = String(data: response.body, encoding: .utf8) ?? "<non-utf8 \(response.body.count) bytes>"
            logger.info("[update/\(attempt)] ← [\(response.statusCode)] body: \(responseBody)")
            return response
        }

        do {
            try await Retry.run(policy: retryPolicy) { [retryPolicy, auth] _ in
                let token = await auth.currentAccessToken()
                var response = try await performOnce(token: token, attempt: "first")

                // 401 → refresh + retry once (PRD FR-11D.5).
                if response.statusCode == 401 {
                    let refreshed = try await auth.invalidateAndRefresh()
                    response = try await performOnce(token: refreshed, attempt: "refreshed")
                }

                if (200..<300).contains(response.statusCode) {
                    return // success
                }
                if retryPolicy.isRetryable(statusCode: response.statusCode) {
                    throw RetryableError(PayabliTTPError.updateFailed(
                        reason: "HTTP \(response.statusCode)"
                    ))
                }
                throw PayabliTTPError.updateFailed(reason: "HTTP \(response.statusCode)")
            }
            return true
        } catch {
            multicaster.emit(.updateFailed(paymentTransId: paymentTransId, error: String(describing: error)))
            return false
        }
    }

    private func syncPublished() {
        sessionState = sessionManager.sessionState
        isReady = sessionManager.isReady
    }
}

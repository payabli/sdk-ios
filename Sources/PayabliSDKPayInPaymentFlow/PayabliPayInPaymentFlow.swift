import Foundation
import PayabliSDKCore

/// Unified Pay In component for storing payment methods and running v2 MoneyIn
/// auth/capture flows.
///
/// The component can exchange card or ACH data for a stored payment method, or
/// send card, ACH, stored-method, cash, check, or cloud-device payment requests
/// to the v2 MoneyIn endpoints. It does not log, persist, or expose raw PAN,
/// CVV, bank account, or routing values after submission.
@MainActor
public final class PayabliPayInPaymentFlow: NSObject, ObservableObject, PayabliComponent {
    public nonisolated static let componentId = "payInPaymentFlow"
    public nonisolated static let sessionTier: PayabliSessionTier = .tier1Transactional
    public nonisolated static let requiredPermissions = [
        "tokenstorage:add",
        "moneyin:getpaid",
        "moneyin:authorize",
        "moneyin:capture"
    ]

    @Published public private(set) var isSubmitting: Bool = false
    @Published public private(set) var lastResult: PayabliPayInPaymentFlowResult?

    public var lastStoredPaymentMethod: PayabliPayInPaymentFlowStoredPaymentMethod? {
        lastResult?.storedPaymentMethod
    }

    public private(set) var entryPoint: String
    public private(set) var environment: PayabliEnvironment
    /// Mints the key for an attempt that supplied none.
    ///
    /// Settable rather than an initialiser parameter: every initialiser here already carries seven, and
    /// a test only needs this pinned before it submits. Not public, so a host cannot supply one.
    var newIdempotencyKey: @Sendable () -> String = { UUID().uuidString }

    /// Reads a clock that keeps running while the device sleeps, so a key held across a locked phone
    /// expires on the wall rather than on processor time.
    var monotonicNow: @Sendable () -> ContinuousClock.Instant = { ContinuousClock().now }

    @Published public private(set) var operation: PayabliPayInPaymentFlowOperation
    @Published public private(set) var requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration?

    private let accessTokenProvider: PayabliPayInPaymentFlowAccessTokenProvider
    private let injectedTransport: (any PayabliTransport)?
    private let diagnostics: PayabliPayInPaymentFlowDiagnostics
    private var client: PayInPaymentFlowClient
    private var tokenStorageClient: PayInPaymentFlowTokenStorageClient
    private var activeSubmissionCount = 0

    /// The attempt in flight.
    private var attemptInFlight: HeldAttempt?

    /// The attempt that ended without an answer, whose key the next submit of the same payment sends.
    ///
    /// Nothing here identifies a payer or an instrument. What a repeat has to match is the payment, and
    /// the instrument is not part of that: a payer reaching for a second card is retrying the same
    /// purchase, and the card before it may already have been charged for that purchase.
    private var unresolvedAttempt: HeldAttempt?

    /// A key this SDK is holding, and what it was reserved for.
    private struct HeldAttempt {
        let key: String
        let scope: AttemptScope
        let reservedAt: ContinuousClock.Instant

        /// True when this SDK minted the key or reused one it was already holding.
        ///
        /// A key the caller supplied is never held: it is theirs to resend, and holding one would mean
        /// sending a value the caller did not choose for a submission they did not make.
        let ours: Bool

        /// True when the key was already being held rather than minted for this attempt, which is what
        /// makes a conflict on this submission something the key's own handling caused.
        let reused: Bool
    }

    /// Which payment an attempt was for, so a held key is reused for that one and no other.
    ///
    /// Every field is an identifier or an amount the caller set. None of them names a payer or an
    /// instrument, so holding this costs no exposure: a merchant that distinguishes two payments of
    /// equal value distinguishes them here too, by the order, the customer, the account or the
    /// subscription the request already carries.
    struct AttemptScope: Equatable {
        let route: String
        let amount: Double
        let currency: String?
        let orderId: String?
        let accountId: String?
        let subscriptionId: Int64?
        let customerId: Int64?
        let customerNumber: String?
        let transactionId: String?

        init(
            route: String,
            _ request: PayabliPayInPaymentFlowRequest,
            transactionId: String? = nil
        ) {
            self.init(
                route: route,
                request.paymentDetails,
                orderId: request.orderId,
                accountId: request.accountId,
                subscriptionId: request.subscriptionId,
                customerData: request.customerData,
                transactionId: transactionId
            )
        }

        init(
            route: String,
            _ details: PayabliPayInPaymentFlowPaymentDetails,
            orderId: String? = nil,
            accountId: String? = nil,
            subscriptionId: Int64? = nil,
            customerData: PayabliPayInPaymentFlowCustomerData? = nil,
            transactionId: String? = nil
        ) {
            self.route = route
            amount = details.totalAmount
            currency = details.currency
            self.orderId = orderId
            self.accountId = accountId
            self.subscriptionId = subscriptionId
            customerId = customerData?.customerId
            customerNumber = customerData?.customerNumber
            self.transactionId = transactionId
        }
    }

    public init(
        entryPoint: String,
        environment: PayabliEnvironment,
        accessTokenProvider: @escaping PayabliPayInPaymentFlowAccessTokenProvider,
        diagnostics: PayabliPayInPaymentFlowDiagnostics = .disabled,
        operation: PayabliPayInPaymentFlowOperation = .storePaymentMethod,
        requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration? = nil
    ) {
        self.entryPoint = entryPoint
        self.environment = environment
        self.operation = operation
        self.requestConfiguration = requestConfiguration
        self.accessTokenProvider = accessTokenProvider
        injectedTransport = nil
        self.diagnostics = diagnostics
        // The chain attaches the credential, so neither client stamps one. This surface has no
        // session, so it gets the bearer and not the 401 recovery.
        let baseTransport = PayabliService(
            environment: environment,
            readToken: Self.guardedRead(accessTokenProvider)
        )
        client = PayInPaymentFlowClient(
            transport: baseTransport,
            baseURL: environment.baseURL,
            diagnostics: diagnostics
        )
        tokenStorageClient = PayInPaymentFlowTokenStorageClient(
            transport: baseTransport,
            baseURL: environment.baseURL,
            diagnostics: diagnostics
        )
        super.init()
    }

    init(
        entryPoint: String,
        environment: PayabliEnvironment,
        accessTokenProvider: @escaping PayabliPayInPaymentFlowAccessTokenProvider,
        transport: (any PayabliTransport)? = nil,
        diagnostics: PayabliPayInPaymentFlowDiagnostics = .disabled,
        operation: PayabliPayInPaymentFlowOperation = .storePaymentMethod,
        requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration? = nil
    ) {
        self.entryPoint = entryPoint
        self.environment = environment
        self.operation = operation
        self.requestConfiguration = requestConfiguration
        self.accessTokenProvider = accessTokenProvider
        self.injectedTransport = transport
        self.diagnostics = diagnostics
        let baseTransport = transport
            ?? PayabliService(
                environment: environment,
                readToken: Self.guardedRead(accessTokenProvider)
            )
        client = PayInPaymentFlowClient(
            transport: baseTransport,
            baseURL: environment.baseURL,
            diagnostics: diagnostics
        )
        tokenStorageClient = PayInPaymentFlowTokenStorageClient(
            transport: baseTransport,
            baseURL: environment.baseURL,
            diagnostics: diagnostics
        )
        super.init()
    }

    public convenience init(
        config: PayabliConfig,
        accessTokenProvider: @escaping PayabliPayInPaymentFlowAccessTokenProvider,
        diagnostics: PayabliPayInPaymentFlowDiagnostics = .disabled,
        operation: PayabliPayInPaymentFlowOperation = .storePaymentMethod,
        requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration? = nil
    ) {
        self.init(
            entryPoint: config.entryPoint,
            environment: config.environment,
            accessTokenProvider: accessTokenProvider,
            diagnostics: diagnostics,
            operation: operation,
            requestConfiguration: requestConfiguration
        )
    }

    convenience init(
        config: PayabliConfig,
        accessTokenProvider: @escaping PayabliPayInPaymentFlowAccessTokenProvider,
        transport: (any PayabliTransport)? = nil,
        diagnostics: PayabliPayInPaymentFlowDiagnostics = .disabled,
        operation: PayabliPayInPaymentFlowOperation = .storePaymentMethod,
        requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration? = nil
    ) {
        self.init(
            entryPoint: config.entryPoint,
            environment: config.environment,
            accessTokenProvider: accessTokenProvider,
            transport: transport,
            diagnostics: diagnostics,
            operation: operation,
            requestConfiguration: requestConfiguration
        )
    }

    /// Convenience for tests or ephemeral access tokens.
    ///
    /// Do not pass a long-lived private API token from production app code.
    /// Prefer the `accessTokenProvider` initializer and fetch a scoped token
    /// from the host application's backend just before submission.
    public convenience init(
        accessToken: String,
        entryPoint: String,
        environment: PayabliEnvironment,
        diagnostics: PayabliPayInPaymentFlowDiagnostics = .disabled,
        operation: PayabliPayInPaymentFlowOperation = .storePaymentMethod,
        requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration? = nil
    ) {
        let provider: PayabliPayInPaymentFlowAccessTokenProvider = { accessToken }
        self.init(
            entryPoint: entryPoint,
            environment: environment,
            accessTokenProvider: provider,
            diagnostics: diagnostics,
            operation: operation,
            requestConfiguration: requestConfiguration
        )
    }

    convenience init(
        accessToken: String,
        entryPoint: String,
        environment: PayabliEnvironment,
        transport: (any PayabliTransport)? = nil,
        diagnostics: PayabliPayInPaymentFlowDiagnostics = .disabled,
        operation: PayabliPayInPaymentFlowOperation = .storePaymentMethod,
        requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration? = nil
    ) {
        let provider: PayabliPayInPaymentFlowAccessTokenProvider = { accessToken }
        self.init(
            entryPoint: entryPoint,
            environment: environment,
            accessTokenProvider: provider,
            transport: transport,
            diagnostics: diagnostics,
            operation: operation,
            requestConfiguration: requestConfiguration
        )
    }

    public func configure(config: PayabliConfig) {
        entryPoint = config.entryPoint
        environment = config.environment
        let baseTransport = injectedTransport
            ?? PayabliService(
                environment: config.environment,
                readToken: Self.guardedRead(accessTokenProvider)
            )
        client = PayInPaymentFlowClient(
            transport: baseTransport,
            baseURL: config.environment.baseURL,
            diagnostics: diagnostics
        )
        tokenStorageClient = PayInPaymentFlowTokenStorageClient(
            transport: baseTransport,
            baseURL: config.environment.baseURL,
            diagnostics: diagnostics
        )
    }

    public func configure(config: PayabliConfig, theme _: PayabliTheme) {
        configure(config: config)
    }

    /// The host's provider, trimmed and refused when empty, in the shape the chain reads.
    ///
    /// One read per request. The chain is what sends the credential, and a provider may mint a
    /// different token per call, so a check elsewhere would either spend a second call or validate a
    /// token that was not sent.
    ///
    /// A provider failure is tagged `PayInProviderFailure` on the way out. The read runs inside
    /// `transport.perform` now, so anything thrown from it reaches the diagnostics sink, which renders
    /// a non-SDK error whole and redacts only digit sequences shaped like a card number — and a host's
    /// provider error can name its own backend. The tag is what lets both clients keep it out of the
    /// record while still handing the host back its own error, which the Objective-C bridge relies on.
    private static func guardedRead(
        _ provider: @escaping PayabliPayInPaymentFlowAccessTokenProvider
    ) -> @Sendable () async throws -> String {
        {
            let minted: String
            do {
                minted = try await provider()
            } catch {
                throw PayInProviderFailure(underlying: error)
            }
            let token = minted.payabliCaptureTrimmed
            guard !token.isEmpty else {
                throw PayabliPayInPaymentFlowError.missingAccessToken
            }
            return token
        }
    }

    public func configure(
        operation: PayabliPayInPaymentFlowOperation,
        requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration? = nil
    ) {
        self.operation = operation
        self.requestConfiguration = requestConfiguration
    }

    public func configure(
        requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration
    ) {
        self.requestConfiguration = requestConfiguration
    }

    public func submitConfigured(
        _ request: PayabliPayInPaymentFlowRequest
    ) async throws -> PayabliPayInPaymentFlowResult {
        switch operation {
        case .storePaymentMethod:
            throw PayabliPayInPaymentFlowError.invalidInput("A payment method input is required for storePaymentMethod.")
        case .capture:
            return try await capture(request)
        case .authorize:
            return try await authorize(request)
        }
    }

    public func submitConfigured(
        _ paymentMethod: PayabliPayInPaymentFlowMethodInput,
        options: PayabliPayInPaymentFlowTokenStorageOptions = PayabliPayInPaymentFlowTokenStorageOptions()
    ) async throws -> PayabliPayInPaymentFlowResult {
        guard operation == .storePaymentMethod else {
            throw PayabliPayInPaymentFlowError.invalidInput("storePaymentMethod operation is required to store a payment method.")
        }

        let storedPaymentMethod = try await addPaymentMethod(paymentMethod, options: options)
        return PayabliPayInPaymentFlowResult(storedPaymentMethod: storedPaymentMethod)
    }

    /// Stores card or ACH payment data using `POST /api/TokenStorage/add`.
    public func addPaymentMethod(
        _ paymentMethod: PayabliPayInPaymentFlowMethodInput,
        options: PayabliPayInPaymentFlowTokenStorageOptions = PayabliPayInPaymentFlowTokenStorageOptions()
    ) async throws -> PayabliPayInPaymentFlowStoredPaymentMethod {
        try beginSubmission()
        defer { endSubmission() }

        let storedPaymentMethod = try await tokenStorageClient.addMethod(
            entryPoint: entryPoint,
            paymentMethod: paymentMethod,
            options: options
        )
        lastResult = PayabliPayInPaymentFlowResult(storedPaymentMethod: storedPaymentMethod)
        return storedPaymentMethod
    }

    public func addCard(
        _ card: PayabliPayInPaymentFlowCardData,
        options: PayabliPayInPaymentFlowTokenStorageOptions = PayabliPayInPaymentFlowTokenStorageOptions()
    ) async throws -> PayabliPayInPaymentFlowStoredPaymentMethod {
        try await addPaymentMethod(.card(card), options: options)
    }

    public func addACH(
        _ ach: PayabliPayInPaymentFlowACHData,
        options: PayabliPayInPaymentFlowTokenStorageOptions = PayabliPayInPaymentFlowTokenStorageOptions()
    ) async throws -> PayabliPayInPaymentFlowStoredPaymentMethod {
        try await addPaymentMethod(.ach(ach), options: options)
    }

    /// Authorizes and captures a transaction in one step using
    /// `POST /api/v2/MoneyIn/getpaid`.
    public func capture(
        _ request: PayabliPayInPaymentFlowRequest
    ) async throws -> PayabliPayInPaymentFlowResult {
        try await submit {
            try await client.capture(
                entryPoint: entryPoint,
                request: request,
                idempotencyKey: self.reserveKey(
                    request.idempotencyKey,
                    for: AttemptScope(route: "capture", request)
                )
            )
        }
    }

    /// Authorizes a card-data transaction using
    /// `POST /api/v2/MoneyIn/authorize`.
    ///
    /// Only card data is supported for authorization today. ACH, stored
    /// methods, cash, check, and cloud transactions cannot be authorized with
    /// this endpoint. Apple Pay can be added as a separate authorizable method
    /// when the SDK supports that flow.
    public func authorize(
        _ request: PayabliPayInPaymentFlowRequest
    ) async throws -> PayabliPayInPaymentFlowResult {
        try await submit {
            try await client.authorize(
                entryPoint: entryPoint,
                request: request,
                idempotencyKey: self.reserveKey(
                    request.idempotencyKey,
                    for: AttemptScope(route: "authorize", request)
                )
            )
        }
    }

    /// Captures a prior authorization using
    /// `POST /api/v2/MoneyIn/capture/{transId}`.
    public func captureAuthorizedTransaction(
        _ request: PayabliPayInPaymentFlowAuthorizedRequest
    ) async throws -> PayabliPayInPaymentFlowResult {
        try await submit {
            try await client.captureAuthorized(
                request,
                idempotencyKey: self.reserveKey(
                    request.idempotencyKey,
                    for: AttemptScope(
                        route: "captureAuthorized",
                        request.paymentDetails,
                        transactionId: request.transId
                    )
                )
            )
        }
    }

    /// The key this attempt sends: the caller's when it set one, the held key when the last attempt at
    /// this same payment ended without an answer, otherwise a fresh one.
    ///
    /// A money-moving request always carries one. Left absent, the service recognises no repeat, so an
    /// attempt that was cancelled or timed out cannot be made again without risking a second payment.
    ///
    /// Reusing the held key is what makes the next submit a repeat rather than a second payment, and it
    /// is the safe direction of the two: the service refuses a repeat inside its window, where a fresh
    /// key would take the money again. It is held only for an outcome nobody knows and only for the
    /// same payment, so a different one is never refused as a duplicate.
    ///
    /// A key the caller supplied is refused rather than replaced when it cannot be sent, which is the
    /// client's to decide, since substituting one would send a key the caller does not hold.
    private func reserveKey(_ supplied: String?, for scope: AttemptScope) -> String {
        let now = monotonicNow()
        if let supplied {
            attemptInFlight = HeldAttempt(
                key: supplied, scope: scope, reservedAt: now, ours: false, reused: false
            )
            return supplied
        }
        if let held = unresolvedAttempt {
            let expired = held.reservedAt.duration(to: now) >= Self.heldKeyWindow
            if expired {
                // Sending it now would read as protection and be a second payment: the service no
                // longer holds the key, so it executes the request rather than refusing it.
                unresolvedAttempt = nil
            } else if held.scope == scope {
                attemptInFlight = HeldAttempt(
                    key: held.key, scope: scope, reservedAt: held.reservedAt, ours: true, reused: true
                )
                return held.key
            }
        }
        let minted = newIdempotencyKey()
        attemptInFlight = HeldAttempt(
            key: minted, scope: scope, reservedAt: now, ours: true, reused: false
        )
        return minted
    }

    /// How long a key this SDK holds is still worth sending.
    ///
    /// The service keeps a key for two minutes from the moment it reads the request. This clock starts
    /// when the key is reserved, which is before the request leaves the device, so the window that can
    /// be relied on is shorter than the service's by however long the attempt took. Short by a margin
    /// rather than exact, because the two directions cost different things: stopping early mints a key
    /// where a repeat would have been refused, and stopping late sends a key the service has forgotten,
    /// which it executes.
    private static let heldKeyWindow: Duration = .seconds(90)

    /// Records how the attempt in flight ended.
    ///
    /// An outcome nobody knows holds the key for the next submit of the same payment; anything else
    /// drops it, an answer being an answer. A submission that reserved no key leaves a held one alone,
    /// so storing a method between an interrupted payment and its retry does not lose the key.
    private func settleAttempt(_ failure: (any Error)?) {
        guard let attempt = attemptInFlight else { return }
        attemptInFlight = nil
        guard attempt.ours else {
            // A key the caller chose is not this SDK's to hold, whatever happened to it.
            return
        }
        if let failure, !Self.answersTheRequest(failure) {
            unresolvedAttempt = attempt
        } else {
            unresolvedAttempt = nil
        }
    }

    /// Whether a failure says anything about the request the key went out for.
    ///
    /// A refusal, a conflict and a validation failure the service made all answer it, so the key has
    /// nothing left to protect. Nothing else does. A credential the service rejected, a refusal to act
    /// at all, and anything that never left the device leave the earlier attempt exactly as unknown as
    /// it was, so its key is still the one the next submission has to send. Discarding it there is what
    /// turns a corrected retry into a second payment.
    private static func answersTheRequest(_ failure: any Error) -> Bool {
        if let flow = failure as? PayabliPayInPaymentFlowError {
            switch flow {
            case .invalidInput, .missingAccessToken, .submissionInProgress, .submissionInterrupted:
                return false
            case .transactionFailed, .repeatRefused:
                return true
            }
        }
        switch (failure as? any PayabliError)?.code {
        case .paymentDeclined, .conflict, .validation:
            return true
        default:
            return false
        }
    }

    private func submit(
        _ operation: () async throws -> PayabliPayInPaymentFlowResult
    ) async throws -> PayabliPayInPaymentFlowResult {
        try beginSubmission()
        defer { endSubmission() }

        do {
            let result = try await operation()
            settleAttempt(nil)
            lastResult = result
            return result
        } catch {
            let repeated = attemptInFlight?.reused ?? false
            settleAttempt(error)
            if repeated, (error as? any PayabliError)?.code == .conflict {
                // The key this SDK chose to send is why this failed, which is the one thing about its
                // handling a caller has to be told.
                throw PayabliPayInPaymentFlowError.repeatRefused
            }
            throw error
        }
    }

    private func beginSubmission() throws {
        guard activeSubmissionCount == 0 else {
            throw PayabliPayInPaymentFlowError.submissionInProgress
        }
        activeSubmissionCount = 1
        isSubmitting = true
    }

    private func endSubmission() {
        activeSubmissionCount = max(0, activeSubmissionCount - 1)
        isSubmitting = activeSubmissionCount > 0
    }
}

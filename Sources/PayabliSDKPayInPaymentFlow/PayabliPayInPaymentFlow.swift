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
    package nonisolated static let componentId = "payInPaymentFlow"
    package nonisolated static let sessionTier: PayabliSessionTier = .tier1Transactional
    package nonisolated static let requiredPermissions = [
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

    @Published public private(set) var operation: PayabliPayInPaymentFlowOperation
    @Published public private(set) var requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration?

    private let accessTokenProvider: PayabliPayInPaymentFlowAccessTokenProvider
    private let injectedTransport: (any PayabliTransport)?
    private let diagnostics: PayabliPayInPaymentFlowDiagnostics
    private var client: PayInPaymentFlowClient
    private var tokenStorageClient: PayInPaymentFlowTokenStorageClient
    private var activeSubmissionCount = 0

    /// The attempt in flight, and the payment it is for.
    private var attemptInFlight: (key: String, scope: AttemptScope)?

    /// The attempt that ended without an answer, whose key the next submit of the same payment sends.
    ///
    /// Nothing here identifies a payer or an instrument: what a repeat has to match is the payment, and
    /// this holds only what says which one that is.
    private var unresolvedAttempt: (key: String, scope: AttemptScope)?

    /// Which payment an attempt was for, so a held key is reused for that one and no other.
    ///
    /// The route is part of it because authorizing and capturing the same amount are different
    /// requests, and the transaction is, because two authorizations of equal value are as well.
    struct AttemptScope: Equatable {
        let route: String
        let amount: Double
        let currency: String?
        let transactionId: String?

        init(
            route: String,
            _ details: PayabliPayInPaymentFlowPaymentDetails,
            transactionId: String? = nil
        ) {
            self.route = route
            amount = details.totalAmount
            currency = details.currency
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
                    for: AttemptScope(route: "capture", request.paymentDetails)
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
                    for: AttemptScope(route: "authorize", request.paymentDetails)
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
        if let supplied {
            attemptInFlight = (supplied, scope)
            return supplied
        }
        if let unresolvedAttempt, unresolvedAttempt.scope == scope {
            attemptInFlight = unresolvedAttempt
            return unresolvedAttempt.key
        }
        let minted = newIdempotencyKey()
        attemptInFlight = (minted, scope)
        return minted
    }

    /// Records how the attempt in flight ended.
    ///
    /// An outcome nobody knows holds the key for the next submit of the same payment; anything else
    /// drops it, an answer being an answer. A submission that reserved no key leaves a held one alone,
    /// so storing a method between an interrupted payment and its retry does not lose the key.
    private func settleAttempt(_ failure: (any Error)?) {
        guard let attempt = attemptInFlight else { return }
        attemptInFlight = nil
        if case .submissionInterrupted = failure as? PayabliPayInPaymentFlowError {
            unresolvedAttempt = attempt
        } else {
            unresolvedAttempt = nil
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
            settleAttempt(error)
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

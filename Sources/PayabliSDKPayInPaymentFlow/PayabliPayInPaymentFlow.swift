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
    @Published public private(set) var operation: PayabliPayInPaymentFlowOperation
    @Published public private(set) var requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration?

    private var session: PayabliSession?
    private let injectedTransport: (any PayabliTransport)?
    private let diagnostics: PayabliPayInPaymentFlowDiagnostics
    private var client: PayInPaymentFlowClient
    private var tokenStorageClient: PayInPaymentFlowTokenStorageClient
    private var activeSubmissionCount = 0

    /// Builds the flow on a session, which carries the credential and the transport that sends it.
    ///
    /// The entry point and the environment come from the session's configuration, so a flow and the
    /// session it runs on cannot disagree about which merchant or which host they are for.
    public init(
        session: PayabliSession,
        diagnostics: PayabliPayInPaymentFlowDiagnostics = .disabled,
        operation: PayabliPayInPaymentFlowOperation = .storePaymentMethod,
        requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration? = nil
    ) {
        self.entryPoint = session.config.entryPoint
        self.environment = session.config.environment
        self.operation = operation
        self.requestConfiguration = requestConfiguration
        self.session = session
        injectedTransport = nil
        self.diagnostics = diagnostics
        client = PayInPaymentFlowClient(
            transport: session.transport,
            baseURL: session.config.environment.baseURL,
            diagnostics: diagnostics
        )
        tokenStorageClient = PayInPaymentFlowTokenStorageClient(
            transport: session.transport,
            baseURL: session.config.environment.baseURL,
            diagnostics: diagnostics
        )
        super.init()
    }

    /// A flow on a transport supplied whole, for tests that answer requests themselves.
    ///
    /// There is no token source here because there is nothing to authenticate: the transport given
    /// is the one used, and a fake one never reads a credential.
    init(
        entryPoint: String,
        environment: PayabliEnvironment,
        transport: any PayabliTransport,
        diagnostics: PayabliPayInPaymentFlowDiagnostics = .disabled,
        operation: PayabliPayInPaymentFlowOperation = .storePaymentMethod,
        requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration? = nil
    ) {
        self.entryPoint = entryPoint
        self.environment = environment
        self.operation = operation
        self.requestConfiguration = requestConfiguration
        session = nil
        injectedTransport = transport
        self.diagnostics = diagnostics
        client = PayInPaymentFlowClient(
            transport: transport,
            baseURL: environment.baseURL,
            diagnostics: diagnostics
        )
        tokenStorageClient = PayInPaymentFlowTokenStorageClient(
            transport: transport,
            baseURL: environment.baseURL,
            diagnostics: diagnostics
        )
        super.init()
    }

    /// Points the flow at a different merchant or host.
    ///
    /// A configuration carries a token provider, so this builds the session it describes rather than
    /// reusing the one the flow was made with, which was for a different entry point.
    public func configure(config: PayabliConfig) {
        entryPoint = config.entryPoint
        environment = config.environment
        let transport: any PayabliTransport
        if let injectedTransport {
            transport = injectedTransport
        } else {
            let rebuilt = PayabliSession(config: config)
            session = rebuilt
            transport = rebuilt.transport
        }
        client = PayInPaymentFlowClient(
            transport: transport,
            baseURL: config.environment.baseURL,
            diagnostics: diagnostics
        )
        tokenStorageClient = PayInPaymentFlowTokenStorageClient(
            transport: transport,
            baseURL: config.environment.baseURL,
            diagnostics: diagnostics
        )
    }

    public func configure(config: PayabliConfig, theme _: PayabliTheme) {
        configure(config: config)
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
            try await client.capture(entryPoint: entryPoint, request: request)
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
            try await client.authorize(entryPoint: entryPoint, request: request)
        }
    }

    /// Captures a prior authorization using
    /// `POST /api/v2/MoneyIn/capture/{transId}`.
    public func captureAuthorizedTransaction(
        _ request: PayabliPayInPaymentFlowAuthorizedRequest
    ) async throws -> PayabliPayInPaymentFlowResult {
        try await submit {
            try await client.captureAuthorized(request)
        }
    }

    private func submit(
        _ operation: () async throws -> PayabliPayInPaymentFlowResult
    ) async throws -> PayabliPayInPaymentFlowResult {
        try beginSubmission()
        defer { endSubmission() }

        let result = try await operation()
        lastResult = result
        return result
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

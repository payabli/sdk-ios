import Foundation
import PayabliSDKCore

/// Card and payment transaction component for v2 MoneyIn auth/capture flows.
///
/// The component sends card, ACH, stored-method, cash, check, or cloud-device
/// payment requests to the v2 MoneyIn endpoints. It does not log, persist, or
/// expose raw PAN, CVV, bank account, or routing values after submission.
@MainActor
public final class PayabliPaymentCapture: NSObject, ObservableObject, PayabliComponent {
    public nonisolated static let componentId = "paymentCapture"
    public nonisolated static let sessionTier: PayabliSessionTier = .tier1Transactional
    public nonisolated static let requiredPermissions = [
        "moneyin:getpaid",
        "moneyin:authorize",
        "moneyin:capture"
    ]

    @Published public private(set) var isSubmitting: Bool = false
    @Published public private(set) var lastResult: PayabliPaymentCaptureResult?

    public private(set) var entryPoint: String
    public private(set) var environment: PayabliEnvironment
    public private(set) var operation: PayabliPaymentCaptureOperation
    public private(set) var requestConfiguration: PayabliPaymentCaptureRequestConfiguration?

    private let accessTokenProvider: PayabliPaymentCaptureAccessTokenProvider
    private let injectedTransport: (any PayabliTransport)?
    private let diagnostics: PayabliPaymentCaptureDiagnostics
    private var client: PaymentCaptureClient

    public init(
        entryPoint: String,
        environment: PayabliEnvironment,
        accessTokenProvider: @escaping PayabliPaymentCaptureAccessTokenProvider,
        transport: (any PayabliTransport)? = nil,
        diagnostics: PayabliPaymentCaptureDiagnostics = .disabled,
        operation: PayabliPaymentCaptureOperation = .capture,
        requestConfiguration: PayabliPaymentCaptureRequestConfiguration? = nil
    ) {
        self.entryPoint = entryPoint
        self.environment = environment
        self.operation = operation
        self.requestConfiguration = requestConfiguration
        self.accessTokenProvider = accessTokenProvider
        self.injectedTransport = transport
        self.diagnostics = diagnostics
        let baseTransport = transport ?? PayabliService(environment: environment)
        client = PaymentCaptureClient(
            transport: baseTransport,
            accessTokenProvider: accessTokenProvider,
            baseURL: environment.baseURL,
            diagnostics: diagnostics
        )
        super.init()
    }

    public convenience init(
        config: PayabliConfig,
        accessTokenProvider: @escaping PayabliPaymentCaptureAccessTokenProvider,
        transport: (any PayabliTransport)? = nil,
        diagnostics: PayabliPaymentCaptureDiagnostics = .disabled,
        operation: PayabliPaymentCaptureOperation = .capture,
        requestConfiguration: PayabliPaymentCaptureRequestConfiguration? = nil
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
        transport: (any PayabliTransport)? = nil,
        diagnostics: PayabliPaymentCaptureDiagnostics = .disabled,
        operation: PayabliPaymentCaptureOperation = .capture,
        requestConfiguration: PayabliPaymentCaptureRequestConfiguration? = nil
    ) {
        let provider: PayabliPaymentCaptureAccessTokenProvider = { accessToken }
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
        let baseTransport = injectedTransport ?? PayabliService(environment: config.environment)
        client = PaymentCaptureClient(
            transport: baseTransport,
            accessTokenProvider: accessTokenProvider,
            baseURL: config.environment.baseURL,
            diagnostics: diagnostics
        )
    }

    public func configure(config: PayabliConfig, theme _: PayabliTheme) {
        configure(config: config)
    }

    public func configure(
        operation: PayabliPaymentCaptureOperation,
        requestConfiguration: PayabliPaymentCaptureRequestConfiguration? = nil
    ) {
        self.operation = operation
        self.requestConfiguration = requestConfiguration
    }

    public func configure(
        requestConfiguration: PayabliPaymentCaptureRequestConfiguration
    ) {
        self.requestConfiguration = requestConfiguration
    }

    public func submitConfigured(
        _ request: PayabliPaymentCaptureRequest
    ) async throws -> PayabliPaymentCaptureResult {
        switch operation {
        case .capture:
            return try await capture(request)
        case .authorize:
            return try await authorize(request)
        }
    }

    /// Authorizes and captures a transaction in one step using
    /// `POST /api/v2/MoneyIn/getpaid`.
    public func capture(
        _ request: PayabliPaymentCaptureRequest
    ) async throws -> PayabliPaymentCaptureResult {
        try await submit {
            try await client.capture(entryPoint: entryPoint, request: request)
        }
    }

    /// Authorizes a card transaction using `POST /api/v2/MoneyIn/authorize`.
    ///
    /// ACH, cash, check, and cloud transactions cannot be authorized with this
    /// endpoint. Use `capture(_:)` for a one-step sale/capture transaction.
    public func authorize(
        _ request: PayabliPaymentCaptureRequest
    ) async throws -> PayabliPaymentCaptureResult {
        try await submit {
            try await client.authorize(entryPoint: entryPoint, request: request)
        }
    }

    /// Captures a prior authorization using
    /// `POST /api/v2/MoneyIn/capture/{transId}`.
    public func captureAuthorizedTransaction(
        _ request: PayabliPaymentCaptureAuthorizedRequest
    ) async throws -> PayabliPaymentCaptureResult {
        try await submit {
            try await client.captureAuthorized(request)
        }
    }

    private func submit(
        _ operation: () async throws -> PayabliPaymentCaptureResult
    ) async throws -> PayabliPaymentCaptureResult {
        isSubmitting = true
        defer { isSubmitting = false }

        let result = try await operation()
        lastResult = result
        return result
    }
}

import Foundation
import PayabliSDKCore

/// PAN and ACH payment method component.
///
/// The component exchanges sensitive payment data for a Payabli stored method
/// ID using `/api/TokenStorage/add`. It does not log, persist, or expose raw
/// PAN, CVV, bank account, or routing values after submission.
@MainActor
public final class PayabliPaymentMethod: NSObject, ObservableObject, PayabliComponent {
    public nonisolated static let componentId = "paymentMethod"
    public nonisolated static let sessionTier: PayabliSessionTier = .tier1Transactional
    public nonisolated static let requiredPermissions = ["tokenstorage:add"]

    @Published public private(set) var isSubmitting: Bool = false
    @Published public private(set) var lastStoredPaymentMethod: PayabliStoredPaymentMethod?

    public private(set) var entryPoint: String
    public private(set) var environment: PayabliEnvironment

    private let accessTokenProvider: PayabliPaymentMethodAccessTokenProvider
    private let injectedTransport: (any PayabliTransport)?
    private let diagnostics: PayabliPaymentMethodDiagnostics
    private var client: TokenStorageClient

    public init(
        entryPoint: String,
        environment: PayabliEnvironment,
        accessTokenProvider: @escaping PayabliPaymentMethodAccessTokenProvider,
        transport: (any PayabliTransport)? = nil,
        diagnostics: PayabliPaymentMethodDiagnostics = .disabled
    ) {
        self.entryPoint = entryPoint
        self.environment = environment
        self.accessTokenProvider = accessTokenProvider
        self.injectedTransport = transport
        self.diagnostics = diagnostics
        let baseTransport = transport ?? PayabliService(environment: environment)
        self.client = TokenStorageClient(
            transport: baseTransport,
            accessTokenProvider: accessTokenProvider,
            baseURL: environment.baseURL,
            diagnostics: diagnostics
        )
        super.init()
    }

    public convenience init(
        config: PayabliConfig,
        accessTokenProvider: @escaping PayabliPaymentMethodAccessTokenProvider,
        transport: (any PayabliTransport)? = nil,
        diagnostics: PayabliPaymentMethodDiagnostics = .disabled
    ) {
        self.init(
            entryPoint: config.entryPoint,
            environment: config.environment,
            accessTokenProvider: accessTokenProvider,
            transport: transport,
            diagnostics: diagnostics
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
        diagnostics: PayabliPaymentMethodDiagnostics = .disabled
    ) {
        let provider: PayabliPaymentMethodAccessTokenProvider = { accessToken }
        self.init(
            entryPoint: entryPoint,
            environment: environment,
            accessTokenProvider: provider,
            transport: transport,
            diagnostics: diagnostics
        )
    }

    public func configure(config: PayabliConfig) {
        self.entryPoint = config.entryPoint
        self.environment = config.environment
        let baseTransport = injectedTransport ?? PayabliService(environment: config.environment)
        self.client = TokenStorageClient(
            transport: baseTransport,
            accessTokenProvider: accessTokenProvider,
            baseURL: config.environment.baseURL,
            diagnostics: diagnostics
        )
    }

    public func addPaymentMethod(
        _ paymentMethod: PayabliPaymentMethodInput,
        options: PayabliPaymentMethodOptions = PayabliPaymentMethodOptions()
    ) async throws -> PayabliStoredPaymentMethod {
        isSubmitting = true
        defer { isSubmitting = false }

        let result = try await client.addMethod(
            entryPoint: entryPoint,
            paymentMethod: paymentMethod,
            options: options
        )
        lastStoredPaymentMethod = result
        return result
    }

    public func addCard(
        _ card: PayabliCardPaymentMethodData,
        options: PayabliPaymentMethodOptions = PayabliPaymentMethodOptions()
    ) async throws -> PayabliStoredPaymentMethod {
        try await addPaymentMethod(.card(card), options: options)
    }

    public func addACH(
        _ ach: PayabliACHPaymentMethodData,
        options: PayabliPaymentMethodOptions = PayabliPaymentMethodOptions()
    ) async throws -> PayabliStoredPaymentMethod {
        try await addPaymentMethod(.ach(ach), options: options)
    }
}

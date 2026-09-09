import PayabliSDKCore
@testable import PayabliSDKPayInPaymentFlow

/// A flow on a real session, for the tests whose subject is the flow rather than the network.
///
/// `token` is what the session's provider answers with. The entry point is a literal here, which is
/// the only thing `PayabliConfig.init` rejects, so the construction cannot fail.
@MainActor
func flowOnSession(
    token: String = "access-token",
    entryPoint: String = "entry",
    environment: PayabliEnvironment = .sandbox,
    diagnostics: PayabliPayInPaymentFlowDiagnostics = .disabled,
    operation: PayabliPayInPaymentFlowOperation = .storePaymentMethod,
    requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration? = nil
) -> PayabliPayInPaymentFlow {
    let config = try! PayabliConfig(
        entryPoint: entryPoint,
        environment: environment,

        tokenProvider: { token }
    )
    return PayabliPayInPaymentFlow(
        session: PayabliSession(config: config),
        diagnostics: diagnostics,
        operation: operation,
        requestConfiguration: requestConfiguration
    )
}

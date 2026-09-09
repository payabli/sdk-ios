import PayabliSDKCore
import PayabliSDKPayInPaymentFlow

/// Where this app's card-not-present flows are built.
///
/// One per operation, because a flow is fixed to the operation it was built for.
/// The app holds the handles these return and never the flow inside them.
@MainActor
enum PayInSessions {
    /// A session for one operation's token endpoint.
    ///
    /// The initialiser rejects an empty entry point, which is a constant here, so this app treats a
    /// rejection as a build it should not ship. A host reading one from its own backend catches
    /// instead, and shows the payer something.
    private static func session(
        entryPoint: String,
        tokenProvider: @escaping PayabliTokenRefresh
    ) -> PayabliSession {
        do {
            return PayabliSession(config: try PayabliConfig(
                entryPoint: entryPoint,
                environment: DemoConfiguration.environment.sdkEnvironment,

                tokenProvider: tokenProvider
            ))
        } catch {
            preconditionFailure("The entry point is not usable: \(error)")
        }
    }

    /// Storing an instrument for later.
    static func storedMethod() -> PayInFlowHandle {
        PayInFlowHandle(
            PayabliPayInPaymentFlow(
                session: session(
                    entryPoint: DemoConfiguration.entryPoint,
                    tokenProvider: { try await Secrets.fetchPaymentMethodAccessToken() }
                ),
                diagnostics: .qaLogging(
                    enabled: Secrets.paymentMethodDiagnosticsEnabled,
                    store: .paymentMethod
                )
            )
        )
    }

    /// Taking a payment now.
    ///
    /// The customer switch that governs the launch request does not exist yet at
    /// this point, and its own default is the same answer, so the launch request
    /// states it rather than reading it.
    static func capture() -> PayInFlowHandle {
        PayInFlowHandle(
            PayabliPayInPaymentFlow(
                session: session(
                    entryPoint: DemoConfiguration.entryPoint,
                    tokenProvider: { try await Secrets.fetchPaymentCaptureAccessToken() }
                ),
                diagnostics: .qaLogging(
                    enabled: Secrets.paymentCaptureDiagnosticsEnabled,
                    store: .paymentCapture
                ),
                operation: .capture,
                requestConfiguration: PayInRequests.freshCapture(suppliesCustomer: true)
            )
        )
    }

    /// A flow for a canvas preview, which makes no network call.
    static func preview(capturing: Bool = false) -> PayInFlowHandle {
        PayInFlowHandle(
            PayabliPayInPaymentFlow(
                session: session(
                    entryPoint: "preview-entry",
                    tokenProvider: { "preview-token" }
                ),
                operation: capturing ? .capture : .storePaymentMethod,
                requestConfiguration: capturing
                    ? PayabliPayInPaymentFlowRequestConfiguration(
                        paymentDetails: PayabliPayInPaymentFlowPaymentDetails(
                            totalAmount: 1,
                            serviceFee: 0.10,
                            currency: "USD"
                        ),
                        orderDescription: "Preview Payment",
                        orderId: "preview-order",
                        source: "preview",
                        idempotencyKey: "preview-key"
                    )
                    : nil
            )
        )
    }
}

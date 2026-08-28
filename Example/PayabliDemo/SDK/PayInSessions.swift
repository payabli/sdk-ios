import PayabliSDKPayInPaymentFlow

/// Where this app's card-not-present flows are built.
///
/// One per operation, because a flow is fixed to the operation it was built for.
/// The app holds the handles these return and never the flow inside them.
@MainActor
enum PayInSessions {
    /// Storing an instrument for later.
    static func storedMethod() -> PayInFlowHandle {
        PayInFlowHandle(
            PayabliPayInPaymentFlow(
                entryPoint: DemoConfiguration.entryPoint,
                environment: DemoConfiguration.environment.sdkEnvironment,
                accessTokenProvider: {
                    try await Secrets.fetchPaymentMethodAccessToken()
                },
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
                entryPoint: DemoConfiguration.entryPoint,
                environment: DemoConfiguration.environment.sdkEnvironment,
                accessTokenProvider: {
                    try await Secrets.fetchPaymentCaptureAccessToken()
                },
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
                accessToken: "preview-token",
                entryPoint: "preview-entry",
                environment: DemoConfiguration.environment.sdkEnvironment,
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

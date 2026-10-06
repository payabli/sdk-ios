import PayabliSDKCore
import PayabliSDKPayIn

/// Where this app's card-not-present flows are built.
///
/// One per operation, because a flow is fixed to the operation it was built for.
/// The app holds the handles these return and never the flow inside them.
@MainActor
enum PayInSessions {
    /// Storing an instrument for later.
    static func storedMethod(session: PayabliSession) -> PayInFlowHandle {
        PayInFlowHandle(
            PayabliPayIn(
                session: session,
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
    static func capture(session: PayabliSession) -> PayInFlowHandle {
        PayInFlowHandle(
            PayabliPayIn(
                session: session,
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
    static func preview(session: PayabliSession, capturing: Bool = false) -> PayInFlowHandle {
        PayInFlowHandle(
            PayabliPayIn(
                session: session,
                operation: capturing ? .capture : .storePaymentMethod,
                requestConfiguration: capturing
                    ? PayabliPayInRequestConfiguration(
                        paymentDetails: PayabliPayInPaymentDetails(
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

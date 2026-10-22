@testable import PayabliSDKCore
@testable import PayabliSDKPayIn

/// A flow on a real session, for the tests whose subject is the flow rather than the network.
///
/// `token` is what the session's provider answers with. The entry point is a literal here, which is
/// the only thing `PayabliConfig.init` rejects, so the construction cannot fail.
@MainActor
func flowOnSession(
    token: String = "access-token",
    entryPoint: String = "entry",
    environment: PayabliEnvironment = .sandbox,
    operation: PayabliPayInOperation = .storePaymentMethod,
    requestConfiguration: PayabliPayInRequestConfiguration? = nil
) -> PayabliPayIn {
    let config = try! PayabliConfig(
        entryPoint: entryPoint,
        environment: environment,

        tokenProvider: { token }
    )
    return PayabliPayIn(
        session: PayabliSession(config: config, telemetryTransport: DiscardingTelemetryTransport()),
        operation: operation,
        requestConfiguration: requestConfiguration
    )
}

/// Accepts every telemetry batch and sends nothing, so a session built in a test never reaches the network.
struct DiscardingTelemetryTransport: TelemetryTransport {
    func send(_ batch: [TelemetryEvent], droppedSinceLastSend: Int) async -> TelemetrySendOutcome {
        .delivered
    }
}

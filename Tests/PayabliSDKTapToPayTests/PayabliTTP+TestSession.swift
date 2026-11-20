import Foundation
@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils

@available(iOS 16.7, *)
extension PayabliTTP {
    /// A facade on a session of its own, outside the installed one, so a test needs no session reset. Its channel stays
    /// installed in the process recorder until the next install or clear, so a test whose transport reaches a stub
    /// clears it. The session reads as live unless a test says otherwise, since it was never installed.
    convenience init(
        config: PayabliConfig,
        provider: TapToPayProvider,
        attestation: DeviceAttestationService,
        retryPolicy: RetryPolicy = .default,
        session: URLSession? = nil,
        telemetry: any TelemetryTransport = InMemoryTelemetryTransport(),
        isLive: @escaping @Sendable () -> Bool = { true },
        chargeKeys: ChargeKeyStore = ChargeKeyStore()
    ) {
        let payabliSession = PayabliSession(config: config, urlSession: session, telemetryTransport: telemetry)
        TelemetryRecorders.install(payabliSession.telemetry)
        self.init(
            session: payabliSession,
            provider: provider,
            attestation: attestation,
            retryPolicy: retryPolicy,
            isLive: isLive,
            chargeKeys: chargeKeys
        )
    }
}

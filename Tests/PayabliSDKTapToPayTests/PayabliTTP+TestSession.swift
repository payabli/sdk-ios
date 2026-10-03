import Foundation
@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay

extension PayabliTTP {
    /// A facade on a session of its own, outside the installed one, so a test needs no reset.
    convenience init(
        config: PayabliConfig,
        appId: String,
        provider: TapToPayProvider,
        attestation: DeviceAttestationService,
        retryPolicy: RetryPolicy = .default,
        session: URLSession? = nil
    ) {
        self.init(
            session: PayabliSession(config: config, urlSession: session),
            appId: appId,
            provider: provider,
            attestation: attestation,
            retryPolicy: retryPolicy
        )
    }
}

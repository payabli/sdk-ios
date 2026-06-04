import Foundation
import PayabliSDKCore

/// Supplies the bearer access token used by v2 MoneyIn transaction APIs.
///
/// Prefer fetching this value from the host application's backend just before
/// processing a transaction. Do not hard-code private API keys in an app binary.
public typealias PayabliPayInPaymentFlowAccessTokenProvider = @Sendable () async throws -> String

/// Module-level namespace for `PayabliSDKPayInPaymentFlow` metadata.
///
/// The enum name intentionally differs from the module name so library
/// evolution builds do not confuse a namespace with the Swift module itself.
public enum PayabliPayInPaymentFlowModule {
    public static var version: String {
        Bundle(for: VersionMarker.self)
            .infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0.0.0"
    }

    private final class VersionMarker {}
}

import Foundation
import PayabliSDKCore

/// Supplies the bearer access token used to authorize `/api/TokenStorage/add`.
///
/// Prefer fetching this value from the host application's backend just before
/// tokenization. Do not hard-code private API tokens in an app binary.
public typealias PayabliTokenizationAccessTokenProvider = @Sendable () async throws -> String

/// Module-level namespace for `PayabliSDKTokenization` metadata.
///
/// The enum name intentionally differs from the module name so library
/// evolution builds do not confuse a namespace with the Swift module itself.
public enum PayabliTokenizationModule {
    public static var version: String {
        Bundle(for: VersionMarker.self)
            .infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0.0.0"
    }

    private final class VersionMarker {}
}

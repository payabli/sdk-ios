import Foundation
import PayabliSDKTapToPay

/// Where this app's card reader is built.
enum TapToPaySessions {
    /// The terminal the app runs on a device.
    ///
    /// `placeholderAccessToken` only has to survive the initialiser — the SDK
    /// replaces it through the token provider on the first 401, so no synchronous
    /// network call is needed at launch.
    @MainActor
    static func terminal() -> TapToPayTerminal {
        TapToPayTerminal(
            PayabliTTP(
                accessToken: Secrets.placeholderAccessToken,
                tokenProvider: { try await Secrets.fetchAccessToken() },
                entryPoint: DemoConfiguration.entryPoint,
                appId: Secrets.appId,
                environment: DemoConfiguration.environment
            )
        )
    }

    /// A terminal for a canvas preview. Constructed and never initialized, so it
    /// makes no network call and touches neither App Attest nor the reader.
    @MainActor
    static func preview() -> TapToPayTerminal {
        TapToPayTerminal(
            PayabliTTP(
                accessToken: "preview-token",
                tokenProvider: { "preview-token" },
                entryPoint: "preview-entry",
                appId: "PREVIEW0000.\(Bundle.main.bundleIdentifier ?? "preview")",
                environment: DemoConfiguration.environment
            )
        )
    }
}

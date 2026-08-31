import Foundation
import PayabliSDKTapToPay

/// Where this app's card reader is built.
enum TapToPaySessions {
    /// The terminal the app runs on a device.
    ///
    /// `placeholderAccessToken` only has to survive the initialiser — the SDK
    /// replaces it through the token provider on the first 401, so no synchronous
    /// network call is needed at launch.
    ///
    /// The initialiser rejects a token it could not send and an empty entry point.
    /// Both are constants here, so this app treats a rejection as a build it should
    /// not ship. A host reading either from its own backend catches instead, and
    /// shows the payer something.
    @MainActor
    static func terminal() -> TapToPayTerminal {
        do {
            return TapToPayTerminal(
                try PayabliTTP(
                    accessToken: Secrets.placeholderAccessToken,
                    tokenProvider: { try await Secrets.fetchAccessToken() },
                    entryPoint: DemoConfiguration.entryPoint,
                    appId: Secrets.appId,
                    environment: DemoConfiguration.environment.sdkEnvironment
                )
            )
        } catch {
            preconditionFailure("Secrets.swift or the entry point is not usable: \(error)")
        }
    }

    /// A terminal for a canvas preview. Constructed and never initialized, so it
    /// makes no network call and touches neither App Attest nor the reader.
    @MainActor
    static func preview() -> TapToPayTerminal {
        do {
            return TapToPayTerminal(
                try PayabliTTP(
                    accessToken: "preview-token",
                    tokenProvider: { "preview-token" },
                    entryPoint: "preview-entry",
                    appId: "PREVIEW0000.\(Bundle.main.bundleIdentifier ?? "preview")",
                    environment: DemoConfiguration.environment.sdkEnvironment
                )
            )
        } catch {
            preconditionFailure("The preview terminal's own constants are not usable: \(error)")
        }
    }
}

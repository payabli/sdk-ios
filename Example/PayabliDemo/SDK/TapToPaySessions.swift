import Foundation
import PayabliSDKTapToPay

/// Where this app's card reader is built.
enum TapToPaySessions {
    /// The terminal the app runs on a device.
    ///
    /// No token is handed over at launch: the SDK asks the provider for one when it makes its
    /// first request, so nothing here waits on the network.
    ///
    /// The initialiser rejects an empty entry point, which is a constant here, so this app
    /// treats a rejection as a build it should not ship. A host reading one from its own
    /// backend catches instead, and shows the payer something.
    @MainActor
    static func terminal() -> TapToPayTerminal {
        do {
            return TapToPayTerminal(
                try PayabliTTP(
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

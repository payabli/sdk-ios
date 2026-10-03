import Foundation
import PayabliSDKTapToPay

/// Where this app's card reader is built.
enum TapToPaySessions {
    /// The terminal the app runs on a device.
    ///
    /// Runs on the session `DemoSession` started, so it shares the card-not-present flows' token.
    @MainActor
    static func terminal() -> TapToPayTerminal {
        DemoSession.start()
        do {
            return TapToPayTerminal(try PayabliTTP(appId: Secrets.appId))
        } catch {
            preconditionFailure("The terminal could not be built: \(error)")
        }
    }

    /// A terminal for a canvas preview. Constructed and never initialized, so it
    /// makes no network call and touches neither App Attest nor the reader.
    @MainActor
    static func preview() -> TapToPayTerminal {
        DemoSession.startPreview()
        do {
            return TapToPayTerminal(
                try PayabliTTP(appId: "PREVIEW0000.\(Bundle.main.bundleIdentifier ?? "preview")")
            )
        } catch {
            preconditionFailure("The preview terminal's own constants are not usable: \(error)")
        }
    }
}

import SwiftUI
import PayabliSDKCore
import PayabliSDKTapToPay

/// Entry point of the TTP-only demo app.
///
/// The app owns a single `PayabliTTP` instance, instantiated at launch with
/// the partner-supplied access token and exposed to the view tree as an
/// `@StateObject` via `HomeView`.
@main
struct PayabliDemoApp: App {
    @StateObject private var ttp = PayabliTTP(
        accessToken: Secrets.placeholderAccessToken,
        tokenProvider: { try await Secrets.fetchAccessToken() },
        entryPoint: Secrets.entryPoint,
        appId: Secrets.appId,
        environment: .sandbox
    )

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(ttp)
        }
    }
}

import PayabliSDKCore
import PayabliSDKTapToPay
import PayabliSDKTokenization
import SwiftUI

/// Entry point of the Payabli demo app.
///
/// The app owns a single `PayabliTTP` instance, instantiated at launch with
/// the partner-supplied access token, plus a `PayabliTokenization` instance
/// for card/ACH stored-method examples.
@main
struct PayabliDemoApp: App {
    @StateObject private var ttp = PayabliTTP(
        accessToken: Secrets.placeholderAccessToken,
        tokenProvider: { try await Secrets.fetchAccessToken() },
        entryPoint: Secrets.entryPoint,
        appId: Secrets.appId,
        environment: .sandbox
    )
    @StateObject private var tokenization = PayabliTokenization(
        entryPoint: Secrets.entryPoint,
        environment: .sandbox,
        accessTokenProvider: { try await Secrets.fetchTokenizationAccessToken() }
    )

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(ttp)
                .environmentObject(tokenization)
        }
    }
}

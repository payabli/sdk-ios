import SwiftUI
import PayabliSDKCore
import PayabliSDKPayIn

@main
struct PayabliDemoApp: App {
    init() {
        Task { @MainActor in
            await configurePayabli()
        }
    }

    var body: some Scene {
        WindowGroup {
            HomeView()
        }
    }

    /// Fetch an access token from the partner backend, then configure PayIn.
    /// See Secrets.swift.sample for why the token comes from a server endpoint.
    @MainActor
    private func configurePayabli() async {
        do {
            let initialToken = try await Secrets.fetchAccessToken()
            PayabliPayIn.shared.configure(
                config: PayabliConfig(
                    accessToken: initialToken,
                    tokenProvider: { try await Secrets.fetchAccessToken() },
                    entryPoint: Secrets.entryPoint,
                    environment: .sandbox
                ),
                theme: PayabliTheme(
                    primaryColorHex: "#10B981",
                    cornerRadius: 10
                )
            )
        } catch {
            print("⚠️ Failed to configure PayabliSDK: \(error)")
        }
    }
}

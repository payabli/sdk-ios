import Foundation
import os
import SwiftUI

@main
struct PayabliDemoQAApp: App {
    @StateObject private var paymentMethod = PayInSessions.storedMethod()

    @StateObject private var paymentCapture = PayInSessions.capture()

    @StateObject private var terminal = TapToPaySessions.terminal()

    /// One owner for the token probes, so a tab that has finished its backend
    /// step still reflects an answer another tab has since had. One entry per
    /// token function, because a backend may scope them separately.
    @StateObject private var tokenProbes = TokenProbeResults(
        fetchCardPresent: { try await Secrets.fetchAccessToken() },
        fetchStoredMethod: { try await Secrets.fetchPaymentMethodAccessToken() },
        fetchCapture: { try await Secrets.fetchPaymentCaptureAccessToken() }
    )

    /// Shared so the Configuration tab can set it and the payment tabs can
    /// read it. In memory only.
    @StateObject private var demoCustomer = DemoCustomerSetting()

    var body: some Scene {
        WindowGroup {
            TabView {
                PaymentMethodQAView(paymentFlow: paymentMethod)
                    .tabItem {
                        Label("Save", systemImage: "creditcard")
                    }

                PaymentCaptureQAView(paymentFlow: paymentCapture)
                    .tabItem {
                        Label("Capture", systemImage: "dollarsign.circle")
                    }

                PaymentTapToPayQAView(terminal: terminal)
                    .tabItem {
                        Label("TapToPay", systemImage: "wave.3.right")
                    }

                ConfigurationQAView()
                    .tabItem {
                        Label("Config", systemImage: "gearshape")
                    }
            }
            // The app-wide tint. The palette lives in one Swift file rather than an
            // asset catalogue, so it is set here instead of by an AccentColor asset.
            .tint(.payabliPrimary)
            .environmentObject(tokenProbes)
            .environmentObject(demoCustomer)
        }
    }
}

#Preview {
    TabView {
        PaymentMethodQAView(paymentFlow: PayInSessions.preview())
            .tabItem {
                Label("Save", systemImage: "creditcard")
            }

        PaymentCaptureQAView(paymentFlow: PayInSessions.preview(capturing: true))
            .tabItem {
                Label("Capture", systemImage: "dollarsign.circle")
            }

        // The terminal is constructed but never initialized here, so the preview
        // makes no network call and touches neither App Attest nor the reader.
        // Pre-flight still renders, and reports the Simulator honestly.
        PaymentTapToPayQAView(terminal: TapToPaySessions.preview())
            .tabItem {
                Label("TapToPay", systemImage: "wave.3.right")
            }

        ConfigurationQAView()
            .tabItem {
                Label("Config", systemImage: "gearshape")
            }
    }
    .environmentObject(TokenProbeResults.inert())
    .environmentObject(DemoCustomerSetting())
}

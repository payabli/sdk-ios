import Foundation
import os
import PayabliSDKCore
import SwiftUI

@main
struct PayabliDemoQAApp: App {
    init() {
        DemoSession.start()
    }

    @StateObject private var paymentMethod = PayInSessions.storedMethod()

    @StateObject private var paymentCapture = PayInSessions.capture()

    @StateObject private var terminal = TapToPaySessions.terminal()

    @StateObject private var simpleCapture = PayInSessions.capture()

    @StateObject private var simpleSave = PayInSessions.storedMethod()

    @AppStorage(ConfigurationQAView.showsSimpleCaptureKey) private var showsSimpleCapture = false

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

                if showsSimpleCapture {
                    SimpleCaptureView(captureFlow: simpleCapture, saveFlow: simpleSave)
                        .tabItem {
                            Label("S-Capture", systemImage: "dollarsign.circle")
                        }
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

        SimpleCaptureView(
            captureFlow: PayInSessions.preview(capturing: true),
            saveFlow: PayInSessions.preview()
        )
        .tabItem {
            Label("S-Capture", systemImage: "dollarsign.circle")
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

/// The one session this app runs on, started before any flow or terminal is built.
///
/// Each token function in `Secrets` stays its own setting for the probes on the Config tab. The
/// session takes one provider, because the process has one session for every capability.
enum DemoSession {
    /// Idempotent: a second call with the same values returns the session already started.
    ///
    /// The entry point is a constant here, so this app treats a rejection as a build it should not
    /// ship. A host reading one from its own backend catches instead, and shows the payer something.
    ///
    /// A canvas preview gets a session no merchant answers to, so a preview cannot reach a backend.
    @discardableResult
    static func start() -> PayabliSession {
        let isPreview = ProcessInfo.processInfo.environment["XCODE_RUNNING_FOR_PREVIEWS"] == "1"
        do {
            return try PayabliSession.initialize(config: PayabliConfig(
                entryPoint: isPreview ? "preview-entry" : DemoConfiguration.entryPoint,
                environment: DemoConfiguration.environment.sdkEnvironment,
                tokenProvider: isPreview ? { "preview-token" } : { try await Secrets.fetchAccessToken() }
            ))
        } catch {
            preconditionFailure("The session could not start: \(error)")
        }
    }
}

import Foundation
import os
import PayabliSDKPayInPaymentFlow
import PayabliSDKTapToPay
import SwiftUI

@main
struct PayabliDemoQAApp: App {
    @StateObject private var paymentMethod = PayabliPayInPaymentFlow(
        entryPoint: DemoConfiguration.entryPoint,
        environment: DemoConfiguration.environment,
        accessTokenProvider: {
            return try await Secrets.fetchPaymentMethodAccessToken()
        },
        diagnostics: .qaLogging(
            enabled: Secrets.paymentMethodDiagnosticsEnabled,
            store: .paymentMethod
        )
    )

    @StateObject private var paymentCapture = PayabliPayInPaymentFlow(
        entryPoint: DemoConfiguration.entryPoint,
        environment: DemoConfiguration.environment,
        accessTokenProvider: {
            return try await Secrets.fetchPaymentCaptureAccessToken()
        },
        diagnostics: .qaLogging(
            enabled: Secrets.paymentCaptureDiagnosticsEnabled,
            store: .paymentCapture
        ),
        operation: .capture,
        // The switch that governs this does not exist yet at this point, and its own default
        // is the same answer, so the launch request states it rather than reading it.
        requestConfiguration: PaymentCaptureQAView.freshRequestConfiguration(suppliesCustomer: true)
    )

    /// Card-present terminal. `placeholderAccessToken` only has to survive the
    /// `@StateObject` initialiser — the SDK replaces it through `tokenProvider`
    /// on the first 401, so no synchronous network call is needed at launch.
    @StateObject private var terminal = PayabliTTP(
        accessToken: Secrets.placeholderAccessToken,
        tokenProvider: { try await Secrets.fetchAccessToken() },
        entryPoint: DemoConfiguration.entryPoint,
        appId: Secrets.appId,
        environment: DemoConfiguration.environment
    )

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
        PaymentMethodQAView(
            paymentFlow: PayabliPayInPaymentFlow(
                accessToken: "preview-token",
                entryPoint: "preview-entry",
                environment: DemoConfiguration.environment
            )
        )
        .tabItem {
            Label("Save", systemImage: "creditcard")
        }

        PaymentCaptureQAView(
            paymentFlow: PayabliPayInPaymentFlow(
                accessToken: "preview-token",
                entryPoint: "preview-entry",
                environment: DemoConfiguration.environment,
                operation: .capture,
                requestConfiguration: PayabliPayInPaymentFlowRequestConfiguration(
                    paymentDetails: PayabliPayInPaymentFlowPaymentDetails(
                        totalAmount: 1,
                        serviceFee: 0.10,
                        currency: "USD"
                    ),
                    orderDescription: "Preview Payment",
                    orderId: "preview-order",
                    source: "preview",
                    idempotencyKey: "preview-key"
                )
            )
        )
        .tabItem {
            Label("Capture", systemImage: "dollarsign.circle")
        }
        // The terminal is constructed but never initialized here, so the preview
        // makes no network call and touches neither App Attest nor the reader.
        // Pre-flight still renders, and reports the Simulator honestly.
        PaymentTapToPayQAView(
            terminal: PayabliTTP(
                accessToken: "preview-token",
                tokenProvider: { "preview-token" },
                entryPoint: "preview-entry",
                appId: "PREVIEW0000.\(Bundle.main.bundleIdentifier ?? "preview")",
                environment: DemoConfiguration.environment
            )
        )
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

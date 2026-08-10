import Foundation
import os
import PayabliSDKPayInPaymentFlow
import PayabliSDKTapToPay
import SwiftUI

@main
struct PayabliDemoQAApp: App {
    @StateObject private var paymentMethod = PayabliPayInPaymentFlow(
        entryPoint: Secrets.entryPoint,
        environment: DemoConfiguration.environment,
        accessTokenProvider: {
            return try await Secrets.fetchPaymentMethodAccessToken()
        },
        diagnostics: .qaLogging(enabled: Secrets.paymentMethodDiagnosticsEnabled,
                                store: .paymentMethod)
    )

    @StateObject private var paymentCapture = PayabliPayInPaymentFlow(
        entryPoint: Secrets.entryPoint,
        environment: DemoConfiguration.environment,
        accessTokenProvider: {
            return try await Secrets.fetchPaymentCaptureAccessToken()
        },
        diagnostics: .qaLogging(enabled: Secrets.paymentCaptureDiagnosticsEnabled,
                                store: .paymentCapture),
        operation: .capture,
        requestConfiguration: PaymentCaptureQAView.freshRequestConfiguration()
    )

    /// Card-present terminal. `placeholderAccessToken` only has to survive the
    /// `@StateObject` initialiser — the SDK replaces it through `tokenProvider`
    /// on the first 401, so no synchronous network call is needed at launch.
    @StateObject private var terminal = PayabliTTP(
        accessToken: Secrets.placeholderAccessToken,
        tokenProvider: { try await Secrets.fetchAccessToken() },
        entryPoint: Secrets.entryPoint,
        appId: Secrets.appId,
        environment: DemoConfiguration.environment
    )

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
}


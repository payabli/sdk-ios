import Foundation
import os
import PayabliSDKPayInPaymentFlow
import SwiftUI

@MainActor
final class PaymentMethodQADiagnosticsStore: ObservableObject {
    static let shared = PaymentMethodQADiagnosticsStore()

    @Published private(set) var messages: [String] = []

    func append(_ message: String) {
        messages.append(message)
        if messages.count > 20 {
            messages.removeFirst(messages.count - 20)
        }
    }
}

@MainActor
final class PaymentCaptureQADiagnosticsStore: ObservableObject {
    static let shared = PaymentCaptureQADiagnosticsStore()

    @Published private(set) var messages: [String] = []

    func append(_ message: String) {
        messages.append(message)
        if messages.count > 20 {
            messages.removeFirst(messages.count - 20)
        }
    }
}

@main
struct PaymentMethodQAApp: App {
    @StateObject private var paymentMethod = PayabliPayInPaymentFlow(
        entryPoint: Secrets.entryPoint,
        environment: PaymentMethodQAConfiguration.environment,
        accessTokenProvider: {
            return try await Secrets.fetchPaymentMethodAccessToken()
        },
        diagnostics: Self.paymentMethodDiagnostics
    )

    @StateObject private var paymentCapture = PayabliPayInPaymentFlow(
        entryPoint: Secrets.entryPoint,
        environment: PaymentMethodQAConfiguration.environment,
        accessTokenProvider: {
            return try await Secrets.fetchPaymentCaptureAccessToken()
        },
        diagnostics: Self.paymentCaptureDiagnostics,
        operation: .capture,
        requestConfiguration: Self.paymentCaptureRequestConfiguration
    )

    var body: some Scene {
        WindowGroup {
            TabView {
                PaymentMethodQAView(paymentFlow: paymentMethod)
                    .tabItem {
                        Label("Method", systemImage: "creditcard")
                    }

                PaymentCaptureQAView(paymentFlow: paymentCapture)
                    .tabItem {
                        Label("Capture", systemImage: "dollarsign.circle")
                    }
            }
        }
    }

    private static var paymentCaptureRequestConfiguration: PayabliPayInPaymentFlowRequestConfiguration {
        PayabliPayInPaymentFlowRequestConfiguration(
            paymentDetails: PayabliPayInPaymentFlowPaymentDetails(
                totalAmount: 1,
                serviceFee: 0.10,
                currency: "USD"
            ),
            orderDescription: "Payment Capture QA",
            orderId: "ios-payment-capture-qa",
            source: "ios-payment-capture-qa",
            idempotencyKey: UUID().uuidString,
            achValidation: true,
            forceCustomerCreation: true
        )
    }

    private static var paymentMethodDiagnostics: PayabliPayInPaymentFlowDiagnostics {
        guard Secrets.paymentMethodDiagnosticsEnabled else { return .disabled }

        return .enabled { entry in
            var lines = [
                "[PayabliPayInPaymentFlowDiagnostics] \(entry.phase.rawValue.uppercased()) \(entry.method) \(entry.url)"
            ]
            if let statusCode = entry.statusCode {
                lines.append("statusCode=\(statusCode)")
            }
            if let durationMilliseconds = entry.durationMilliseconds {
                lines.append("durationMilliseconds=\(durationMilliseconds)")
            }
            lines.append("headers=\(entry.headers)")
            if let body = entry.body {
                lines.append("body=\(body)")
            }
            if let errorDescription = entry.errorDescription {
                lines.append("error=\(errorDescription)")
            }
            let message = lines.joined(separator: "\n")
            print(message)
            Logger(
                subsystem: "com.payabli.demo.paymentmethodqa",
                category: "PaymentMethodDiagnostics"
            ).info("\(message, privacy: .public)")
            Task { @MainActor in
                PaymentMethodQADiagnosticsStore.shared.append(message)
            }
        }
    }

    private static var paymentCaptureDiagnostics: PayabliPayInPaymentFlowDiagnostics {
        guard Secrets.paymentCaptureDiagnosticsEnabled else { return .disabled }

        return .enabled { entry in
            var lines = [
                "[PayabliPayInPaymentFlowDiagnostics] \(entry.phase.rawValue.uppercased()) \(entry.method) \(entry.url)"
            ]
            if let statusCode = entry.statusCode {
                lines.append("statusCode=\(statusCode)")
            }
            if let durationMilliseconds = entry.durationMilliseconds {
                lines.append("durationMilliseconds=\(durationMilliseconds)")
            }
            lines.append("headers=\(entry.headers)")
            if let body = entry.body {
                lines.append("body=\(body)")
            }
            if let errorDescription = entry.errorDescription {
                lines.append("error=\(errorDescription)")
            }
            let message = lines.joined(separator: "\n")
            print(message)
            Logger(
                subsystem: "com.payabli.demo.paymentmethodqa",
                category: "PaymentCaptureDiagnostics"
            ).info("\(message, privacy: .public)")
            Task { @MainActor in
                PaymentCaptureQADiagnosticsStore.shared.append(message)
            }
        }
    }
}

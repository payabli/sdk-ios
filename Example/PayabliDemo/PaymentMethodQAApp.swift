import Foundation
import os
import PayabliSDKCore
import PayabliSDKPaymentCapture
import PayabliSDKPaymentMethod
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
    @StateObject private var paymentMethod = PayabliPaymentMethod(
        entryPoint: Secrets.entryPoint,
        environment: PaymentMethodQAConfiguration.environment,
        accessTokenProvider: {
            if Secrets.paymentMethodMockSuccessEnabled || Secrets.paymentMethodMockFailureEnabled {
                return "mock-token"
            }
            return try await Secrets.fetchPaymentMethodAccessToken()
        },
        transport: Self.paymentMethodMockTransport,
        diagnostics: Self.paymentMethodDiagnostics
    )

    @StateObject private var paymentCapture = PayabliPaymentCapture(
        entryPoint: Secrets.entryPoint,
        environment: PaymentMethodQAConfiguration.environment,
        accessTokenProvider: {
            if Secrets.paymentCaptureMockSuccessEnabled || Secrets.paymentCaptureMockFailureEnabled {
                return "mock-token"
            }
            return try await Secrets.fetchPaymentCaptureAccessToken()
        },
        transport: Self.paymentCaptureMockTransport,
        diagnostics: Self.paymentCaptureDiagnostics,
        operation: .capture,
        requestConfiguration: Self.paymentCaptureRequestConfiguration
    )

    var body: some Scene {
        WindowGroup {
            TabView {
                PaymentMethodQAView()
                    .tabItem {
                        Label("Method", systemImage: "creditcard")
                    }

                PaymentCaptureQAView()
                    .tabItem {
                        Label("Capture", systemImage: "dollarsign.circle")
                    }
            }
            .environmentObject(paymentMethod)
            .environmentObject(paymentCapture)
        }
    }

    private static var paymentMethodMockTransport: (any PayabliTransport)? {
        if Secrets.paymentMethodMockFailureEnabled {
            return PaymentMethodQAMockTransport(result: .failure)
        }
        if Secrets.paymentMethodMockSuccessEnabled {
            return PaymentMethodQAMockTransport(result: .success)
        }
        return nil
    }

    private static var paymentCaptureMockTransport: (any PayabliTransport)? {
        if Secrets.paymentCaptureMockFailureEnabled {
            return PaymentCaptureQAMockTransport(result: .failure)
        }
        if Secrets.paymentCaptureMockSuccessEnabled {
            return PaymentCaptureQAMockTransport(result: .success)
        }
        return nil
    }

    private static var paymentCaptureRequestConfiguration: PayabliPaymentCaptureRequestConfiguration {
        PayabliPaymentCaptureRequestConfiguration(
            paymentDetails: PayabliPaymentCapturePaymentDetails(
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

    private static var paymentMethodDiagnostics: PayabliPaymentMethodDiagnostics {
        guard Secrets.paymentMethodDiagnosticsEnabled else { return .disabled }

        return .enabled { entry in
            var lines = [
                "[PayabliPaymentMethodDiagnostics] \(entry.phase.rawValue.uppercased()) \(entry.method) \(entry.url)"
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

    private static var paymentCaptureDiagnostics: PayabliPaymentCaptureDiagnostics {
        guard Secrets.paymentCaptureDiagnosticsEnabled else { return .disabled }

        return .enabled { entry in
            var lines = [
                "[PayabliPaymentCaptureDiagnostics] \(entry.phase.rawValue.uppercased()) \(entry.method) \(entry.url)"
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

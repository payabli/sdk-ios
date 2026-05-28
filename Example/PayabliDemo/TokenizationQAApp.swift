import PayabliSDKTokenization
import SwiftUI
import os

@MainActor
final class TokenizationQADiagnosticsStore: ObservableObject {
    static let shared = TokenizationQADiagnosticsStore()

    @Published private(set) var messages: [String] = []

    func append(_ message: String) {
        messages.append(message)
        if messages.count > 20 {
            messages.removeFirst(messages.count - 20)
        }
    }
}

@main
struct TokenizationQAApp: App {
    @StateObject private var tokenization = PayabliTokenization(
        entryPoint: Secrets.entryPoint,
        environment: TokenizationQAConfiguration.environment,
        accessTokenProvider: {
            if Secrets.tokenizationMockFailureEnabled {
                return "mock-token"
            }
            return try await Secrets.fetchTokenizationAccessToken()
        },
        transport: Secrets.tokenizationMockFailureEnabled ? TokenizationQAMockFailureTransport() : nil,
        diagnostics: Self.tokenizationDiagnostics
    )

    var body: some Scene {
        WindowGroup {
            TokenizationQAView()
                .environmentObject(tokenization)
        }
    }

    private static var tokenizationDiagnostics: PayabliTokenizationDiagnostics {
        guard Secrets.tokenizationDiagnosticsEnabled else { return .disabled }

        return .enabled { entry in
            var lines = [
                "[PayabliTokenizationDiagnostics] \(entry.phase.rawValue.uppercased()) \(entry.method) \(entry.url)"
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
                subsystem: "com.payabli.demo.tokenizationqa",
                category: "TokenizationDiagnostics"
            ).info("\(message, privacy: .public)")
            Task { @MainActor in
                TokenizationQADiagnosticsStore.shared.append(message)
            }
        }
    }
}

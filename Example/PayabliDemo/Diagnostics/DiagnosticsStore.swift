import Foundation
import os
import PayabliSDKPayInPaymentFlow
import SwiftUI

/// Rolling in-memory log of redacted PayIn request/response diagnostics.
///
/// One type, with a named instance per flow.
@MainActor
final class DiagnosticsStore: ObservableObject {
    static let paymentMethod = DiagnosticsStore(category: "PaymentMethodDiagnostics")
    static let paymentCapture = DiagnosticsStore(category: "PaymentCaptureDiagnostics")

    /// `os.Logger` category, so the two flows stay separable in Console.
    let category: String

    private let limit: Int

    @Published private(set) var messages: [String] = []

    init(category: String, limit: Int = 20) {
        self.category = category
        self.limit = limit
    }

    func append(_ message: String) {
        messages.append(message)
        if messages.count > limit {
            messages.removeFirst(messages.count - limit)
        }
    }

    func clear() {
        messages.removeAll()
    }
}

extension PayabliPayInPaymentFlowDiagnostics {
    /// Builds the diagnostics handler for one flow.
    ///
    /// Parameterised by the gating flag, the logger category and the destination
    /// store, which is all the flows differ by.
    ///
    /// The SDK redacts before handing an entry over; nothing here re-redacts, and
    /// nothing here prints a token.
    static func qaLogging(enabled: Bool, store: DiagnosticsStore) -> PayabliPayInPaymentFlowDiagnostics {
        guard enabled else { return .disabled }

        let logger = Logger(
            subsystem: "com.payabli.example.app",
            category: store.category
        )

        return .enabled { entry in
            let request = "[PayabliPayInPaymentFlowDiagnostics] "
                + "\(entry.phase.rawValue.uppercased()) \(entry.method) \(entry.url)"
            var summary = [request]
            if let statusCode = entry.statusCode {
                summary.append("statusCode=\(statusCode)")
            }
            if let durationMilliseconds = entry.durationMilliseconds {
                summary.append("durationMilliseconds=\(durationMilliseconds)")
            }

            var detail = summary
            detail.append("headers=\(entry.headers)")
            if let body = entry.body {
                detail.append("body=\(body)")
            }
            if let errorDescription = entry.errorDescription {
                detail.append("error=\(errorDescription)")
            }

            // The screen gets the whole entry, which is what a developer opened
            // this tab for. The log gets what the request was and how it went: an
            // entry holds headers, a body and an error description, redacted by the
            // SDK but not empty of the service's own words, and `os.Logger` marks
            // every message public.
            let full = detail.joined(separator: "\n")
            logger.info("\(summary.joined(separator: " "), privacy: .public)")
            Task { @MainActor in
                store.append(full)
            }
        }
    }
}

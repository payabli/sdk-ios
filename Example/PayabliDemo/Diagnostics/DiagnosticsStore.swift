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
            var lines = [
                "[PayabliPayInPaymentFlowDiagnostics] "
                    + "\(entry.phase.rawValue.uppercased()) \(entry.method) \(entry.url)"
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
            logger.info("\(message, privacy: .public)")
            Task { @MainActor in
                store.append(message)
            }
        }
    }
}

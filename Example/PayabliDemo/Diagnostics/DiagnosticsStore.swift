import Foundation
import os
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

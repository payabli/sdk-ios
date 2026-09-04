import Foundation

/// Structured logger for the SDK's own diagnostics.
///
/// Subsystem: `com.payabli.sdk`
/// Categories: `auth`, `network`, `tokenization`, `taptopay`, `telemetry`, `core`
///
/// Privacy rules:
/// - Tokens, secrets, credentials: never logged
/// - PAN, CVV, expiry, account and routing numbers: never logged, period
/// - A cardholder or payer name: never logged either. Leave it out of the payload.
/// - Transaction IDs, state names, error codes, durations: loggable
/// - Device identifiers and email addresses: use `redactFully(_:)`
package struct PayabliLogger: Sendable {
    private let sink: any LogSink
    private let category: Category

    package static let subsystem = "com.payabli.sdk"

    package enum Category: String, Sendable, CaseIterable {
        case core
        case auth
        case network
        case tokenization
        case taptopay
        case telemetry
    }

    /// Severity of one record. Internal: what a host may set as a cutoff, and whether there is an off
    /// value, is not settled, and a public ladder would fix the spelling before that decision.
    enum Level: Sendable {
        case debug
        case info
        case warning
        case error
        case fault
    }

    /// The logger a shipping path uses. This is the one place the unified log is named, which is what
    /// makes every layer below take the logger it was given rather than build its own.
    package init(category: Category) {
        self.init(category: category, sink: UnifiedLogSink())
    }

    /// Internal, so it widens what a test can construct and not what production can.
    init(category: Category, sink: any LogSink) {
        self.category = category
        self.sink = sink
    }

    package func debug(_ message: String) {
        sink.write(level: .debug, category: category, message: message)
    }

    package func info(_ message: String) {
        sink.write(level: .info, category: category, message: message)
    }

    package func warning(_ message: String) {
        sink.write(level: .warning, category: category, message: message)
    }

    package func error(_ message: String) {
        sink.write(level: .error, category: category, message: message)
    }

    package func fault(_ message: String) {
        sink.write(level: .fault, category: category, message: message)
    }
}

// MARK: - Redaction helpers

package extension PayabliLogger {
    /// Returns a redacted form of a sensitive string, showing only the last 4
    /// characters. Use for transaction debugging where the full value must never
    /// be logged (e.g. never use this for PAN/CVV — those must be dropped entirely).
    static func redact(_ value: String) -> String {
        guard value.count > 4 else { return "[REDACTED]" }
        return "[REDACTED]…" + String(value.suffix(4))
    }

    /// Returns `"[REDACTED]"`. Use when any trace of the value is unacceptable.
    static func redactFully(_ value: String?) -> String {
        guard value != nil else { return "[nil]" }
        return "[REDACTED]"
    }
}

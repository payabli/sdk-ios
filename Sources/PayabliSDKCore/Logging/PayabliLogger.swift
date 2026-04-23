import Foundation
import os

/// Structured logger wrapping Apple's `os.Logger` with `.private` redaction
/// for sensitive metadata.
///
/// Subsystem: `com.payabli.sdk`
/// Categories: `auth`, `network`, `tokenization`, `taptopay`, `telemetry`, `core`
///
/// See PRD §24.5 and NFR-23.
///
/// Privacy rules:
/// - Tokens, secrets, credentials: redacted (never logged, even as `.private`)
/// - PAN, CVV, account numbers: NEVER logged, period
/// - Transaction IDs, state names, error codes, durations: `.public`
/// - Device IDs, emails, names: `.private`
public struct PayabliLogger: Sendable {
    private let logger: Logger

    public static let subsystem = "com.payabli.sdk"

    public enum Category: String, Sendable {
        case core
        case auth
        case network
        case tokenization
        case taptopay
        case telemetry
    }

    public init(category: Category) {
        self.logger = Logger(subsystem: Self.subsystem, category: category.rawValue)
    }

    public func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    public func info(_ message: String) {
        logger.info("\(message, privacy: .public)")
    }

    public func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    public func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }

    public func fault(_ message: String) {
        logger.fault("\(message, privacy: .public)")
    }

    /// Log a message with a private (redacted) value.
    public func info(_ message: String, private privateValue: String) {
        logger.info("\(message, privacy: .public): \(privateValue, privacy: .private)")
    }

    /// Log a message with a private (redacted) value at error level.
    public func error(_ message: String, private privateValue: String) {
        logger.error("\(message, privacy: .public): \(privateValue, privacy: .private)")
    }
}

// MARK: - Redaction helpers

public extension PayabliLogger {
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

import Foundation
import os

/// SDK log levels, ordered by verbosity.
public enum LogLevel: Int, Sendable {
    case none = 0
    case error = 1
    case info = 2
    case debug = 3
}

/// Lightweight logging wrapper around os.Logger.
/// Respects the configured LogLevel -- messages below the threshold are silently dropped.
/// Automatically redacts sensitive data in non-debug builds via os.Logger privacy.
final class Log {

    static var level: LogLevel = .none

    private static let subsystem = "com.payabli.ttp"

    private let logger: os.Logger
    let category: String

    init(category: String) {
        self.category = category
        self.logger = os.Logger(subsystem: Self.subsystem, category: category)
    }

    func debug(_ message: String) {
        guard Self.level.rawValue >= LogLevel.debug.rawValue else { return }
        logger.debug("\(message, privacy: .private)")
    }

    func info(_ message: String) {
        guard Self.level.rawValue >= LogLevel.info.rawValue else { return }
        logger.info("\(message, privacy: .private)")
    }

    func error(_ message: String) {
        guard Self.level.rawValue >= LogLevel.error.rawValue else { return }
        logger.error("\(message, privacy: .private)")
    }

    // MARK: - Per-module loggers

    static let attestation = Log(category: "attestation")
    static let networking = Log(category: "networking")
    static let cardReader = Log(category: "card-reader")
    static let session = Log(category: "session")
    static let payment = Log(category: "payment")
}

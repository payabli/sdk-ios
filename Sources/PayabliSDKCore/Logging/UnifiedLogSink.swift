import os

/// Writes to the unified log. The only file here that imports `os`.
struct UnifiedLogSink: LogSink {
    func write(level: PayabliLogger.Level, category: PayabliLogger.Category, message: String) {
        let logger = Logger(subsystem: PayabliLogger.subsystem, category: category.rawValue)
        switch level {
        case .debug:
            logger.debug("\(message, privacy: .public)")
        case .info:
            logger.info("\(message, privacy: .public)")
        case .warning:
            logger.warning("\(message, privacy: .public)")
        case .error:
            logger.error("\(message, privacy: .public)")
        case .fault:
            logger.fault("\(message, privacy: .public)")
        }
    }
}

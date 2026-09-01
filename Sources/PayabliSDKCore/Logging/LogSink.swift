/// Where a finished log line is written.
///
/// This, not `PayabliLogger`, is the swap point for a different logging backend: an in-process ring
/// buffer or a recording double receives the same text the unified log does. Anything that shortens a
/// value does so above here, so replacing the sink cannot skip it.
///
/// There is no `isLoggable`: nothing gates a record on a level, and a member no caller reads is one
/// every conformer has to guess at.
protocol LogSink: Sendable {
    func write(level: PayabliLogger.Level, category: PayabliLogger.Category, message: String)
}

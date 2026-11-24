import PayabliSDKCore

package extension TelemetrySessionContext {
    /// A session context for a credential holder built outside a session.
    ///
    /// - Parameter config: the configuration the holder is built with, whose entry point and environment it reports under.
    /// - Parameter sessionId: the identifier its reports carry.
    /// - Returns: a context matching a telemetry channel built for the same configuration.
    static func of(_ config: PayabliConfig, sessionId: String = "test-session") -> TelemetrySessionContext {
        TelemetrySessionContext(sessionId: sessionId, entry: config.entryPoint, environment: config.environment.name)
    }

    /// A sandbox session context for a credential holder whose configuration is built inline.
    ///
    /// - Parameter entry: the entry point of the telemetry channel the test installs, if any.
    /// - Returns: a context with a fixed session identifier.
    static func sandbox(entry: String) -> TelemetrySessionContext {
        TelemetrySessionContext(sessionId: "test-session", entry: entry, environment: "sandbox")
    }
}

import Foundation

/// The session a reported piece of work began under, which its event carries even when it ends under another.
package struct TelemetrySessionContext: Sendable, Equatable {
    package let sessionId: String
    package let entry: String
    package let environment: String
}

/// The process's one installed telemetry channel, and the call every reporting site makes.
///
/// A reporter holds its session, never a channel, so a re-initialize releases the replaced session's channel. Records
/// reach the channel in the order made, off the caller's path; with nothing installed, their properties are never built.
package enum TelemetryRecorders {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var installed: TelemetryClient?
    private nonisolated(unsafe) static var tail: Task<Void, Never>?

    /// Installs `client`, replacing whatever was installed: a re-initialized session reports through its own channel.
    ///
    /// - Parameter client: the channel every later record reaches.
    package static func install(_ client: TelemetryClient) {
        lock.withLock { installed = client }
    }

    /// Removes the installed channel, so a record goes back to costing nothing.
    package static func clear() {
        lock.withLock { installed = nil }
    }

    /// Hands an event to the installed channel, or does nothing.
    ///
    /// - Parameter name: the event's catalog name.
    /// - Parameter properties: the declared properties, built only when a channel is installed.
    /// - Parameter occurredAt: when the reported thing happened.
    /// - Parameter waitsForBatch: holds even a failure for its batch, for a report the send-at-once rule must not move.
    package static func record(
        _ name: String,
        properties: @autoclosure () -> [String: String] = [:],
        occurredAt: Date = Date(),
        waitsForBatch: Bool = false
    ) {
        deliver(name, properties: properties, occurredAt: occurredAt, waitsForBatch: waitsForBatch, session: nil)
    }

    /// Hands an event to the installed channel as belonging to `session`, for work that can end after a re-initialize
    /// replaced the session it began under. A channel for another entry point or environment drops it.
    ///
    /// - Parameter session: the session the work began under.
    /// - Parameter name: the event's catalog name.
    /// - Parameter properties: the declared properties, built only when a channel is installed.
    /// - Parameter occurredAt: when the reported thing happened.
    /// - Parameter waitsForBatch: holds even a failure for its batch, for a report the send-at-once rule must not move.
    package static func recordFor(
        _ session: TelemetrySessionContext,
        _ name: String,
        properties: @autoclosure () -> [String: String] = [:],
        occurredAt: Date = Date(),
        waitsForBatch: Bool = false
    ) {
        deliver(name, properties: properties, occurredAt: occurredAt, waitsForBatch: waitsForBatch, session: session)
    }

    /// Waits until every record made so far has reached its channel, and every send the installed channel started has
    /// ended.
    package static func settled() async {
        let (pending, client) = lock.withLock { (tail, installed) }
        await pending?.value
        await client?.settled()
    }

    /// Sends what the installed channel holds, once every record made so far has reached it.
    package static func flush() async {
        let (pending, client) = lock.withLock { (tail, installed) }
        await pending?.value
        await client?.flush()
    }

    private static func deliver(
        _ name: String,
        properties: () -> [String: String],
        occurredAt: Date,
        waitsForBatch: Bool,
        session: TelemetrySessionContext?
    ) {
        guard let client = lock.withLock({ installed }) else { return }
        let properties = properties()
        lock.withLock {
            let previous = tail
            tail = Task {
                await previous?.value
                await client.emit(
                    name,
                    properties: properties,
                    occurredAt: occurredAt,
                    waitsForBatch: waitsForBatch,
                    session: session
                )
            }
        }
    }
}

package extension TelemetryClient {
    nonisolated var context: TelemetrySessionContext {
        TelemetrySessionContext(sessionId: sessionId, entry: configuration.entry, environment: configuration.environment)
    }
}

import Foundation

/// The session a reported piece of work began under, which its event carries even when it ends under another.
package struct TelemetrySessionContext: Sendable, Equatable {
    package let sessionId: String
    package let entry: String
    package let environment: String
}

/// The process's one installed telemetry channel, and the call every reporter outside the session makes.
///
/// A record is appended to the channel installed when it is made, on the caller's thread, before the call returns;
/// only sending is asynchronous. With nothing installed, a properties argument is never evaluated.
package enum TelemetryRecorders {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var installed: TelemetryClient?
    private nonisolated(unsafe) static var waitingForReplacement: [CheckedContinuation<Void, Never>] = []

    /// Installs `client`, replacing whatever was installed: a re-initialized session reports through its own channel.
    ///
    /// - Parameter client: the channel every later record reaches.
    package static func install(_ client: TelemetryClient) {
        replace(with: client)
    }

    /// Removes the installed channel, so a record goes back to costing nothing.
    package static func clear() {
        replace(with: nil)
    }

    /// Returns once `client` is no longer the installed channel, so every later record reaches another one.
    ///
    /// - Parameter client: the channel being retired.
    package static func replaced(_ client: TelemetryClient) async {
        await withCheckedContinuation { (replaced: CheckedContinuation<Void, Never>) in
            let waits = lock.withLock {
                guard installed === client else { return false }
                waitingForReplacement.append(replaced)
                return true
            }
            if !waits {
                replaced.resume()
            }
        }
    }

    private static func replace(with client: TelemetryClient?) {
        let waiting = lock.withLock {
            installed = client
            defer { waitingForReplacement = [] }
            return waitingForReplacement
        }
        waiting.forEach { $0.resume() }
    }

    /// Appends an event to the installed channel, or does nothing.
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
        guard let client = lock.withLock({ installed }) else { return }
        client.record(name, properties: properties(), occurredAt: occurredAt, waitsForBatch: waitsForBatch)
    }

    /// Appends an event to the installed channel as belonging to `session`, for work that can end after a re-initialize
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
        guard let client = lock.withLock({ installed }) else { return }
        client.record(
            name,
            properties: properties(),
            occurredAt: occurredAt,
            waitsForBatch: waitsForBatch,
            session: session
        )
    }

    /// Waits until every send the installed channel has started, or a record asked for, has ended.
    package static func settled() async {
        let client = lock.withLock { installed }
        await client?.settled()
    }

    /// Sends what the installed channel holds.
    package static func flush() async {
        let client = lock.withLock { installed }
        await client?.flush()
    }
}

package extension TelemetryClient {
    nonisolated var context: TelemetrySessionContext {
        TelemetrySessionContext(sessionId: sessionId, entry: configuration.entry, environment: configuration.environment)
    }
}

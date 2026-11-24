import Foundation

/// The session a reported piece of work began under, which its event carries even when it ends under another.
package struct TelemetrySessionContext: Sendable, Equatable {
    package let sessionId: String
    package let entry: String
    package let environment: String

    /// - Parameter sessionId: the identifier the session's events carry.
    /// - Parameter entry: the session's entry point.
    /// - Parameter environment: the session's environment, by name.
    package init(sessionId: String, entry: String, environment: String) {
        self.sessionId = sessionId
        self.entry = entry
        self.environment = environment
    }
}

/// The process's one installed telemetry channel, and the call every reporter outside the session makes.
///
/// A record is appended to the channel installed when it is made, on the caller's thread, before the call returns;
/// only sending is asynchronous. With nothing installed, a properties argument is never evaluated.
package enum TelemetryRecorders {
    private typealias Replaced = CheckedContinuation<Void, Never>

    private static let lock = NSLock()
    private nonisolated(unsafe) static var installed: TelemetryClient?
    /// Records that read a channel and have not yet appended to it, by channel.
    private nonisolated(unsafe) static var appending: [ObjectIdentifier: Int] = [:]
    private nonisolated(unsafe) static var waitingForReplacement: [(client: ObjectIdentifier, replaced: Replaced)] = []

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

    /// Returns once `client` is no longer the installed channel and every record that read it has been appended, so
    /// nothing can still reach it.
    ///
    /// - Parameter client: the channel being retired.
    package static func replaced(_ client: TelemetryClient) async {
        let id = ObjectIdentifier(client)
        await withCheckedContinuation { (replaced: Replaced) in
            let waits = lock.withLock {
                guard !isReplaced(id) else { return false }
                waitingForReplacement.append((id, replaced))
                return true
            }
            if !waits {
                replaced.resume()
            }
        }
    }

    private static func replace(with client: TelemetryClient?) {
        changing { installed = client }
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
        guard let client = reading() else { return }
        defer { appended(client) }
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
        guard let client = reading() else { return }
        defer { appended(client) }
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

    /// Returns the installed channel, which cannot be replaced until `appended(_:)` is called with it.
    ///
    /// - Returns: the installed channel, or `nil` when none is.
    private static func reading() -> TelemetryClient? {
        lock.withLock {
            guard let client = installed else { return nil }
            appending[ObjectIdentifier(client), default: 0] += 1
            return client
        }
    }

    /// Ends the hold `reading()` took on `client`.
    ///
    /// - Parameter client: the channel the record was appended to.
    private static func appended(_ client: TelemetryClient) {
        let id = ObjectIdentifier(client)
        changing {
            let left = (appending[id] ?? 1) - 1
            appending[id] = left > 0 ? left : nil
        }
    }

    /// Applies `change` under the lock, then resumes every wait whose channel is now replaced.
    ///
    /// - Parameter change: the change to the installed channel or to the records still appending.
    private static func changing(_ change: () -> Void) {
        let ready: [Replaced] = lock.withLock {
            change()
            let ready = waitingForReplacement.filter { isReplaced($0.client) }.map(\.replaced)
            waitingForReplacement.removeAll { isReplaced($0.client) }
            return ready
        }
        ready.forEach { $0.resume() }
    }

    /// Whether the channel is not installed and no record still holds it. Called under the lock.
    ///
    /// - Parameter client: the channel's identity.
    /// - Returns: `true` when nothing can still reach it.
    private static func isReplaced(_ client: ObjectIdentifier) -> Bool {
        installed.map(ObjectIdentifier.init) != client && appending[client] == nil
    }
}

package extension TelemetryClient {
    nonisolated var context: TelemetrySessionContext {
        TelemetrySessionContext(sessionId: sessionId, entry: configuration.entry, environment: configuration.environment)
    }
}

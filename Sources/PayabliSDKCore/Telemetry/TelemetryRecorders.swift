import Foundation

/// The session a reported piece of work began under, which its event carries even when it ends under another.
package struct TelemetrySessionContext: Sendable, Equatable {
    package let sessionId: String
    package let entry: String
    package let environment: String
}

/// The process's one installed telemetry channel, and the call every reporter outside the session makes.
///
/// A record keeps the session installed when it is made and reaches the channel installed when it is delivered, in the
/// order made, off the caller's path. With nothing installed, a properties argument is never evaluated.
package enum TelemetryRecorders {
    private static let lock = NSLock()
    private nonisolated(unsafe) static var installed: TelemetryClient?
    private nonisolated(unsafe) static var tail: Task<Void, Never>?
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

    /// Returns once no record can still reach `client`: another channel, or none, is installed, and every record made
    /// before that has reached its channel.
    ///
    /// - Parameter client: the channel being retired.
    package static func unreachable(_ client: TelemetryClient) async {
        while lock.withLock({ installed === client }) {
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
        let pending = lock.withLock { tail }
        await pending?.value
    }

    private static func replace(with client: TelemetryClient?) {
        let waiting = lock.withLock {
            installed = client
            defer { waitingForReplacement = [] }
            return waitingForReplacement
        }
        waiting.forEach { $0.resume() }
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
        let pending = lock.withLock { tail }
        await pending?.value
        let client = lock.withLock { installed }
        await client?.settled()
    }

    /// Sends what the installed channel holds, once every record made so far has reached it.
    package static func flush() async {
        let pending = lock.withLock { tail }
        await pending?.value
        let client = lock.withLock { installed }
        await client?.flush()
    }

    /// Takes the record's place in the delivery order as it reads the installed channel, before its properties are
    /// built, so a channel retired meanwhile waits for it.
    private static func deliver(
        _ name: String,
        properties: () -> [String: String],
        occurredAt: Date,
        waitsForBatch: Bool,
        session: TelemetrySessionContext?
    ) {
        var built: AsyncStream<[String: String]>.Continuation?
        let stream = AsyncStream<[String: String]>(bufferingPolicy: .bufferingNewest(1)) { built = $0 }
        let reserved: Bool = lock.withLock {
            guard let recordedOn = installed else { return false }
            let previous = tail
            tail = Task {
                await previous?.value
                var reading = stream.makeAsyncIterator()
                guard let properties = await reading.next() else { return }
                let client = lock.withLock { installed } ?? recordedOn
                await client.emit(
                    name,
                    properties: properties,
                    occurredAt: occurredAt,
                    waitsForBatch: waitsForBatch,
                    session: session ?? recordedOn.context
                )
            }
            return true
        }
        guard reserved else { return }
        built?.yield(properties())
        built?.finish()
    }
}

package extension TelemetryClient {
    nonisolated var context: TelemetrySessionContext {
        TelemetrySessionContext(sessionId: sessionId, entry: configuration.entry, environment: configuration.environment)
    }
}

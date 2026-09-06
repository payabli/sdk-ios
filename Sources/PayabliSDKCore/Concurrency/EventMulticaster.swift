import Foundation

/// Multicast emitter for any `Sendable` event type. Every concurrent caller
/// of `stream()` receives all subsequent events.
package final class EventMulticaster<Event: Sendable>: @unchecked Sendable {
    private final class Subscription: @unchecked Sendable {
        let id = UUID()
        let continuation: AsyncStream<Event>.Continuation

        init(continuation: AsyncStream<Event>.Continuation) {
            self.continuation = continuation
        }
    }

    private let lock = NSLock()
    private var subscribers: [Subscription] = []

    package init() {}

    /// Returns an independent `AsyncStream` for an event subscriber. Every
    /// concurrent caller of `stream()` receives all subsequent events emitted
    /// by `emit(_:)`. Subscriptions are cleaned up automatically when the
    /// returned stream's iterator is released or the consuming task is
    /// cancelled.
    package func stream() -> AsyncStream<Event> {
        AsyncStream { continuation in
            let sub = Subscription(continuation: continuation)
            lock.lock()
            subscribers.append(sub)
            lock.unlock()
            continuation.onTermination = { [weak self] _ in
                self?.remove(sub.id)
            }
        }
    }

    /// Broadcasts an event to every currently-active subscriber. Subscribers
    /// added after this call do not receive the event.
    package func emit(_ event: Event) {
        lock.lock()
        let snapshot = subscribers
        lock.unlock()
        for sub in snapshot {
            sub.continuation.yield(event)
        }
    }

    /// Terminates every active stream. Typical use is during SDK teardown so
    /// consumer `for await` loops exit cleanly. Idempotent; new subscribers
    /// added after `finishAll()` start a fresh stream.
    package func finishAll() {
        lock.lock()
        let snapshot = subscribers
        subscribers.removeAll()
        lock.unlock()
        for sub in snapshot {
            sub.continuation.finish()
        }
    }

    private func remove(_ id: UUID) {
        lock.lock()
        defer { lock.unlock() }
        subscribers.removeAll { $0.id == id }
    }
}

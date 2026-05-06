import Foundation

/// Multicast emitter for any `Sendable` event type. Every concurrent caller
/// of `stream()` receives all subsequent events.
public final class EventMulticaster<Event: Sendable>: @unchecked Sendable {

    private final class Subscription: @unchecked Sendable {
        let id = UUID()
        let continuation: AsyncStream<Event>.Continuation

        init(continuation: AsyncStream<Event>.Continuation) {
            self.continuation = continuation
        }
    }

    private let lock = NSLock()
    private var subscribers: [Subscription] = []

    public init() {}

    public func stream() -> AsyncStream<Event> {
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

    public func emit(_ event: Event) {
        lock.lock()
        let snapshot = subscribers
        lock.unlock()
        for sub in snapshot { sub.continuation.yield(event) }
    }

    public func finishAll() {
        lock.lock()
        let snapshot = subscribers
        subscribers.removeAll()
        lock.unlock()
        for sub in snapshot { sub.continuation.finish() }
    }

    private func remove(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        subscribers.removeAll { $0.id == id }
    }
}

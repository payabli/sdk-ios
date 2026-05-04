import Foundation

/// Multicast emitter for `PayabliTTPEvent` — every concurrent caller of
/// `events()` receives all subsequent events (PRD FR-11G.2).
public final class EventMulticaster: @unchecked Sendable {

    private final class Subscription: @unchecked Sendable {
        let id = UUID()
        let continuation: AsyncStream<PayabliTTPEvent>.Continuation

        init(continuation: AsyncStream<PayabliTTPEvent>.Continuation) {
            self.continuation = continuation
        }
    }

    private let lock = NSLock()
    private var subscribers: [Subscription] = []

    public init() {}

    /// Returns an independent stream. Multiple callers receive the same events.
    public func stream() -> AsyncStream<PayabliTTPEvent> {
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

    /// Broadcast an event to all active subscribers.
    public func emit(_ event: PayabliTTPEvent) {
        lock.lock()
        let snapshot = subscribers
        lock.unlock()

        for sub in snapshot {
            sub.continuation.yield(event)
        }
    }

    /// Terminate all active streams. Typically called on SDK teardown.
    public func finishAll() {
        lock.lock()
        let snapshot = subscribers
        subscribers.removeAll()
        lock.unlock()

        for sub in snapshot {
            sub.continuation.finish()
        }
    }

    private func remove(_ id: UUID) {
        lock.lock(); defer { lock.unlock() }
        subscribers.removeAll { $0.id == id }
    }
}

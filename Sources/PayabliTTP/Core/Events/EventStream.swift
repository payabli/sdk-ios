import Foundation

/// Lightweight event bus for the SDK.
/// Internal components call `emit()` to publish events.
/// Partners observe via the public `stream` (AsyncStream).
///
/// Usage (partner side):
///   for await event in payabliTTP.events {
///       switch event { ... }
///   }
final class EventStream {

    private let continuation: AsyncStream<PayabliTTPEvent>.Continuation

    /// Public stream that partners subscribe to.
    let stream: AsyncStream<PayabliTTPEvent>

    init() {
        var captured: AsyncStream<PayabliTTPEvent>.Continuation!
        stream = AsyncStream { continuation in
            captured = continuation
        }
        continuation = captured
    }

    /// Emit a domain event. Called by internal SDK components.
    func emit(_ event: PayabliTTPEvent) {
        continuation.yield(event)
    }

    deinit {
        continuation.finish()
    }
}

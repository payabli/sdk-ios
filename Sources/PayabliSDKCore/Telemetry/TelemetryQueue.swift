import Foundation

/// The events waiting to be sent, bounded so a reporter that outruns delivery costs its oldest events
/// rather than memory, and appended to on the caller's thread under one lock.
///
/// What is evicted is counted, and the count is reported by the next batch that leaves.
final class TelemetryQueue: @unchecked Sendable {
    private let capacity: Int
    private let lock = NSLock()
    private var held: [TelemetryEvent] = []
    private var dropped = 0
    private var offeredSinceLastDrain = 0
    private var closed = false

    /// - Parameter capacity: the most events held at once.
    init(capacity: Int) {
        self.capacity = capacity
    }

    var count: Int {
        lock.withLock { held.count }
    }

    /// The events held, oldest first.
    var events: [TelemetryEvent] {
        lock.withLock { held }
    }

    /// Appends an event, evicting the oldest when the queue is full.
    ///
    /// - Parameter event: the event to hold.
    /// - Returns: how many events have been offered since the last drain that took anything, this one included, or
    ///   `nil` once the queue is closed. A batch returned by `restoreFront` is not counted.
    func offer(_ event: TelemetryEvent) -> Int? {
        offer(contentsOf: [event])
    }

    /// Appends events in order, with nothing another caller offers between them.
    ///
    /// - Parameter events: the events to hold, oldest first.
    /// - Returns: the count `offer(_:)` returns after the last of them, or `nil` once the queue is closed.
    func offer(contentsOf events: [TelemetryEvent]) -> Int? {
        lock.withLock {
            guard !closed else { return nil }
            for event in events {
                if held.count >= capacity {
                    held.removeFirst()
                    dropped += 1
                }
                held.append(event)
                offeredSinceLastDrain += 1
            }
            return offeredSinceLastDrain
        }
    }

    /// Refuses every later offer. What is held stays, for a last drain or a hand-over.
    func close() {
        lock.withLock { closed = true }
    }

    /// Removes and returns the oldest events, in the order they were offered, and restarts the count
    /// `offer` returns when it takes anything.
    ///
    /// - Parameter max: the most events to take.
    /// - Returns: the events taken, empty when nothing waits.
    func drain(_ max: Int) -> [TelemetryEvent] {
        lock.withLock {
            let taken = Array(held.prefix(max))
            held.removeFirst(taken.count)
            if !taken.isEmpty {
                offeredSinceLastDrain = 0
            }
            return taken
        }
    }

    /// Returns how many events were evicted since the count was last taken, and resets it.
    ///
    /// - Returns: the eviction count.
    func takeDropCount() -> Int {
        lock.withLock {
            defer { dropped = 0 }
            return dropped
        }
    }

    /// Adds back a count no accepted batch reported, so the next batch reports it.
    ///
    /// - Parameter count: the count to add back.
    func restoreDropCount(_ count: Int) {
        lock.withLock { dropped += count }
    }

    /// Returns a kept batch to the front of the queue, in order, with the eviction count taken when it left, evicting
    /// the oldest when the return overflows. A closed queue takes it too, so a hand-over keeps it for the successor.
    ///
    /// - Parameter batch: the events the transport kept, oldest first as they were taken.
    /// - Parameter droppedSinceLastSend: the eviction count taken when the batch left.
    func restoreFront(_ batch: [TelemetryEvent], droppedSinceLastSend: Int) {
        lock.withLock {
            held.insert(contentsOf: batch, at: 0)
            dropped += droppedSinceLastSend
            while held.count > capacity {
                held.removeFirst()
                dropped += 1
            }
        }
    }
}

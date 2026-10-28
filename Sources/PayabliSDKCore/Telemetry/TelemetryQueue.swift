/// The events waiting to be sent, bounded so a reporter that outruns delivery costs its oldest events
/// rather than memory.
///
/// What is evicted is counted, and the count is reported by the next batch that leaves.
struct TelemetryQueue {
    private let capacity: Int
    /// The events held, oldest first.
    private(set) var events: [TelemetryEvent] = []
    private var dropped = 0
    private var offeredSinceLastDrain = 0

    /// - Parameter capacity: the most events held at once.
    init(capacity: Int) {
        self.capacity = capacity
    }

    var count: Int {
        events.count
    }

    /// Appends an event, evicting the oldest when the queue is full.
    ///
    /// - Parameter event: the event to hold.
    /// - Returns: how many events have been offered since the last drain that took anything, this one
    ///   included. A batch returned by `restoreFront` is not counted.
    mutating func offer(_ event: TelemetryEvent) -> Int {
        if events.count >= capacity {
            events.removeFirst()
            dropped += 1
        }
        events.append(event)
        offeredSinceLastDrain += 1
        return offeredSinceLastDrain
    }

    /// Removes and returns the oldest events, in the order they were offered, and restarts the count
    /// `offer` returns when it takes anything.
    ///
    /// - Parameter max: the most events to take.
    /// - Returns: the events taken, empty when nothing waits.
    mutating func drain(_ max: Int) -> [TelemetryEvent] {
        let taken = Array(events.prefix(max))
        events.removeFirst(taken.count)
        if !taken.isEmpty {
            offeredSinceLastDrain = 0
        }
        return taken
    }

    /// Returns how many events were evicted since the count was last taken, and resets it.
    ///
    /// - Returns: the eviction count.
    mutating func takeDropCount() -> Int {
        defer { dropped = 0 }
        return dropped
    }

    /// Adds back a count no accepted batch reported, so the next batch reports it.
    ///
    /// - Parameter count: the count to add back.
    mutating func restoreDropCount(_ count: Int) {
        dropped += count
    }

    /// Returns a kept batch to the front of the queue, in the order it was taken, with the eviction
    /// count taken when it left, evicting the oldest when the return overflows the capacity.
    ///
    /// - Parameter batch: the events the transport kept, oldest first as they were taken.
    /// - Parameter droppedSinceLastSend: the eviction count taken when the batch left.
    mutating func restoreFront(_ batch: [TelemetryEvent], droppedSinceLastSend: Int) {
        events.insert(contentsOf: batch, at: 0)
        dropped += droppedSinceLastSend
        while events.count > capacity {
            events.removeFirst()
            dropped += 1
        }
    }
}

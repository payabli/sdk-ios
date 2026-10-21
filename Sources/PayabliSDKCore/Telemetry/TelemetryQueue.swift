/// The events waiting to be sent, bounded so a reporter that outruns delivery costs its oldest events
/// rather than memory.
///
/// What is evicted is counted, and the count rides the next batch that leaves.
struct TelemetryQueue {
    private let capacity: Int
    private var events: [TelemetryEvent] = []
    private var dropped = 0

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
    /// - Returns: how many events the queue holds afterwards.
    mutating func offer(_ event: TelemetryEvent) -> Int {
        if events.count >= capacity {
            events.removeFirst()
            dropped += 1
        }
        events.append(event)
        return events.count
    }

    /// Removes and returns the oldest events, in the order they were offered.
    ///
    /// - Parameter max: the most events to take.
    /// - Returns: the events taken, empty when nothing waits.
    mutating func drain(_ max: Int) -> [TelemetryEvent] {
        let taken = Array(events.prefix(max))
        events.removeFirst(taken.count)
        return taken
    }

    /// Returns how many events were evicted since the count was last taken, and resets it.
    ///
    /// - Returns: the eviction count.
    mutating func takeDropCount() -> Int {
        defer { dropped = 0 }
        return dropped
    }

    /// Adds back a count whose batch did not arrive, so the next batch carries it.
    ///
    /// - Parameter count: the count the failed batch carried.
    mutating func restoreDropCount(_ count: Int) {
        dropped += count
    }
}

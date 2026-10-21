import Foundation
import PayabliSDKCore

/// In-memory `TelemetryTransport` that records every batch sent to it, and the eviction count each carried.
package actor InMemoryTelemetryTransport: TelemetryTransport {
    package private(set) var batches: [[TelemetryEvent]] = []
    /// The eviction count each batch carried, in the order the batches arrived.
    package private(set) var droppedCounts: [Int] = []
    private var refusing = false

    package init() {}

    /// Makes every later batch count as refused, or as accepted again. Refused batches are still recorded.
    ///
    /// - Parameter refusing: whether to refuse.
    package func refuse(_ refusing: Bool) {
        self.refusing = refusing
    }

    @discardableResult
    package func send(_ batch: [TelemetryEvent], droppedSinceLastSend: Int) async -> Bool {
        batches.append(batch)
        droppedCounts.append(droppedSinceLastSend)
        return !refusing
    }

    /// Returns all recorded batches and clears the internal buffer.
    package func drainBatches() -> [[TelemetryEvent]] {
        let snapshot = batches
        batches.removeAll()
        droppedCounts.removeAll()
        return snapshot
    }
}

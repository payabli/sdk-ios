import Foundation
import PayabliSDKCore

/// In-memory `TelemetryTransport` that records every batch sent to it.
package actor InMemoryTelemetryTransport: TelemetryTransport {
    package private(set) var batches: [[TelemetryEvent]] = []
    private var refusing = false
    private var discarding = false

    package init() {}

    /// Makes every later batch count as refused, or as accepted again. Refused batches are still recorded.
    ///
    /// - Parameter refusing: whether to refuse.
    package func refuse(_ refusing: Bool) {
        self.refusing = refusing
    }

    /// Makes every later batch count as discarded, or as accepted again. Discarded batches are still recorded.
    ///
    /// - Parameter discarding: whether to discard.
    package func discard(_ discarding: Bool) {
        self.discarding = discarding
    }

    @discardableResult
    package func send(_ batch: [TelemetryEvent]) async -> TelemetrySendOutcome {
        batches.append(batch)
        if discarding {
            return .discarded
        }
        return refusing ? .kept : .delivered
    }

    /// Returns all recorded batches and clears the internal buffer.
    package func drainBatches() -> [[TelemetryEvent]] {
        let snapshot = batches
        batches.removeAll()
        return snapshot
    }
}

import Foundation
import PayabliSDKCore

/// In-memory `TelemetryTransport` that records every batch sent to it.
///
/// Use in tests to assert that `TelemetryClient` emits the expected events
/// without establishing a real network connection.
///
/// ```swift
/// let transport = InMemoryTelemetryTransport()
/// let client = TelemetryClient(configuration: ..., transport: transport)
/// await client.emit("my.event")
/// let batches = await transport.batches
/// XCTAssertEqual(batches.first?.first?.event, "my.event")
/// ```
public actor InMemoryTelemetryTransport: TelemetryTransport {
    public private(set) var batches: [[TelemetryEvent]] = []

    public init() {}

    public func send(_ batch: [TelemetryEvent]) async {
        batches.append(batch)
    }

    /// Returns all recorded batches and clears the internal buffer.
    public func drainBatches() -> [[TelemetryEvent]] {
        let snapshot = batches
        batches.removeAll()
        return snapshot
    }
}

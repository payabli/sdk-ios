@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

// MARK: - Recording

extension TelemetryClientTests {
    func testARecordNeverWaitsOnASend() async {
        let stalled = StalledTransport()
        let client = TelemetryClient(
            configuration: .init(entry: "test_entry", environment: "sandbox"),
            transport: stalled,
            sleep: clock.sleep,
            lifecycle: lifecycle,
            deviceId: { nil },
            queued: []
        )
        client.record(TelemetryEventName.ttpInitializeFailed, properties: ["outcome": "failed"])
        let inFlight = await stalled.waitUntilSending()

        for _ in 0 ..< 24 {
            client.record(TelemetryEventName.ttpInitializeFailed, properties: ["outcome": "failed"])
        }

        XCTAssertEqual(inFlight + client.bufferedCount, 25, "every record was kept while the send stalled")
        await stalled.release()
        await client.settled()
    }
}

/// A transport whose first send waits until released, so a test can record while a send is stalled.
private actor StalledTransport: TelemetryTransport {
    private var sending: CheckedContinuation<Int, Never>?
    private var size: Int?
    private var held: CheckedContinuation<Void, Never>?
    private var released = false

    func send(_ batch: [TelemetryEvent]) async -> TelemetrySendOutcome {
        guard !released, held == nil else { return .delivered }
        size = batch.count
        sending?.resume(returning: batch.count)
        sending = nil
        await withCheckedContinuation { held = $0 }
        return .delivered
    }

    /// Returns the size of the stalled batch once a send has started.
    func waitUntilSending() async -> Int {
        if let size {
            return size
        }
        return await withCheckedContinuation { sending = $0 }
    }

    func release() {
        released = true
        held?.resume()
        held = nil
    }
}

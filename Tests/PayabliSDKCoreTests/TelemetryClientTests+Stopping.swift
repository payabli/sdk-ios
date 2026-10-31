@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

// MARK: - Stopping

extension TelemetryClientTests {
    func testStoppingSendsEverythingQueuedAndNotJustOneRequest() async {
        let client = makeClient(batchSize: 100, maxEventsPerRequest: 2)
        for index in 0 ..< 30 {
            await record(client, "e\(index)")
        }

        await client.stop()
        await client.settled()

        let batches = await transport.batches
        XCTAssertEqual(batches.count, 15)
        XCTAssertEqual(batches.flatMap { $0 }.map(\.label), (0 ..< 30).map { "e\($0)" })
        let buffered = await client.bufferedCount
        XCTAssertEqual(buffered, 0)
    }

    func testStoppingSendsNoMoreThanSixteenRequests() async {
        let client = makeClient(batchSize: 100, maxEventsPerRequest: 2)
        for index in 0 ..< 40 {
            await record(client, "e\(index)")
        }

        await client.stop()
        await client.settled()

        let batches = await transport.batches
        XCTAssertEqual(batches.count, 16)
        XCTAssertEqual(batches.flatMap { $0 }.map(\.label), (0 ..< 32).map { "e\($0)" })
        let buffered = await client.bufferedCount
        XCTAssertEqual(buffered, 8, "what the bound leaves is not sent")
    }

    func testABatchKeptAfterStopIsDroppedAndTheDrainCarriesOn() async {
        let sink = RecordingLogSink()
        let client = makeClient(
            batchSize: 100,
            maxEventsPerRequest: 2,
            logger: PayabliLogger(category: .telemetry, sink: sink)
        )
        for index in 0 ..< 6 {
            await record(client, "e\(index)")
        }
        await transport.refuse(true)

        await client.stop()
        await client.settled()

        let batches = await transport.batches
        XCTAssertEqual(batches.flatMap { $0 }.map(\.label), (0 ..< 6).map { "e\($0)" })
        let buffered = await client.bufferedCount
        XCTAssertEqual(buffered, 0)
        let dropped = sink.records.filter { $0.message.hasPrefix("telemetry_batch_after_stop") }
        XCTAssertEqual(dropped.map(\.message), Array(repeating: "telemetry_batch_after_stop count=2", count: 3))
        XCTAssertEqual(dropped.map(\.level), Array(repeating: .debug, count: 3))
    }

    func testStoppingDuringASendRunsTheLastDrainAfterItAndDropsWhatIsKept() async {
        let sink = RecordingLogSink()
        let gated = GatedTelemetryTransport()
        let client = TelemetryClient(
            configuration: .init(batchSize: 100, maxEventsPerRequest: 2, entry: "test_entry", environment: "sandbox"),
            transport: gated,
            sleep: clock.sleep,
            lifecycle: lifecycle,
            deviceId: { nil },
            queued: [],
            logger: PayabliLogger(category: .telemetry, sink: sink)
        )
        await gated.reply(with: .kept)
        await recordFailure(client, "a", outcome: "failed")
        await gated.untilHeld()
        await record(client, "b")
        await record(client, "c")
        await record(client, "d")

        await client.stop()
        let flushed = Task { await client.flush() }
        await gated.open()
        await flushed.value

        let sent = await gated.sent
        XCTAssertEqual(sent.map { $0.map(\.label) }, [["a"], ["b", "c"], ["d"]], "the flush waits for the last drain")
        await client.settled()
        let mostAtOnce = await gated.mostAtOnce
        XCTAssertEqual(mostAtOnce, 1)
        let buffered = await client.bufferedCount
        XCTAssertEqual(buffered, 0, "the batch whose send spanned the stop is not queued again")
        let dropped = sink.records.filter { $0.message.hasPrefix("telemetry_batch_after_stop") }
        XCTAssertEqual(
            dropped.map(\.message),
            ["telemetry_batch_after_stop count=1", "telemetry_batch_after_stop count=2", "telemetry_batch_after_stop count=1"]
        )
    }

    func testAHandOverWaitsForASendInFlightAndKeepsTheBatchItCouldNotSend() async {
        let gated = GatedTelemetryTransport()
        // The hand-over cancels the old client's timer before it waits for the send, so the gate opens only after.
        let handingOver = expectation(description: "the hand-over began")
        let old = TelemetryClient(
            configuration: .init(batchSize: 100, entry: "test_entry", environment: "sandbox"),
            transport: gated,
            sleep: { _ in
                do {
                    try await Task.sleep(nanoseconds: .max)
                } catch {
                    handingOver.fulfill()
                    throw error
                }
            },
            lifecycle: lifecycle,
            deviceId: { nil },
            queued: []
        )
        await gated.reply(with: .kept)
        await recordFailure(old, "a", outcome: "failed")
        await gated.untilHeld()
        await record(old, "b")

        let successor = makeClient(predecessor: old)
        await fulfillment(of: [handingOver], timeout: 5)
        await gated.open()
        await successor.settled()

        let batches = await transport.batches
        XCTAssertEqual(batches.flatMap { $0 }.map(\.label), ["a", "b"])
        XCTAssertEqual(Set(batches.flatMap { $0 }.map(\.sessionId)), [old.sessionId])
        let left = await old.bufferedCount
        XCTAssertEqual(left, 0)
    }

    func testDiscardingDropsWhatIsQueuedAndLogsTheCount() async {
        let sink = RecordingLogSink()
        let client = makeClient(batchSize: 100, logger: PayabliLogger(category: .telemetry, sink: sink))
        for index in 0 ..< 3 {
            await record(client, "e\(index)")
        }

        await client.discard()
        await client.flush()

        let batches = await transport.batches
        XCTAssertTrue(batches.isEmpty)
        let buffered = await client.bufferedCount
        XCTAssertEqual(buffered, 0)
        let dropped = sink.records.filter { $0.message.hasPrefix("telemetry_queue_dropped_on_replacement") }
        XCTAssertEqual(dropped.map(\.message), ["telemetry_queue_dropped_on_replacement count=3"])
        XCTAssertEqual(dropped.map(\.level), [.debug])
    }

    func testAFlushAfterStopSendsNothingMore() async {
        let client = makeClient(batchSize: 100, maxEventsPerRequest: 2)
        for index in 0 ..< 40 {
            await record(client, "e\(index)")
        }

        await client.stop()
        await client.flush()
        await client.settled()

        let batches = await transport.batches
        XCTAssertEqual(batches.count, 16)
    }

    func testARecordReachingAStoppedClientIsReported() async {
        let sink = RecordingLogSink()
        let client = makeClient(logger: PayabliLogger(category: .telemetry, sink: sink))

        await client.stop()
        await client.emit(TelemetryEventName.sdkInitialized)
        await client.flush()

        let buffered = await client.bufferedCount
        XCTAssertEqual(buffered, 0)
        let batches = await transport.batches
        XCTAssertTrue(batches.isEmpty)
        let dropped = sink.records.filter { $0.message.hasPrefix("telemetry_event_after_stop") }
        XCTAssertEqual(dropped.map(\.level), [.debug])
        XCTAssertEqual(dropped.map(\.category), [.telemetry])
    }
}

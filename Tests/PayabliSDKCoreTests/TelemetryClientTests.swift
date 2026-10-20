@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

final class TelemetryClientTests: XCTestCase {
    private let clock = ManualTelemetryClock()
    private let lifecycle = ManualAppLifecycle()
    private let transport = InMemoryTelemetryTransport()

    private func makeClient(
        batchSize: Int = 20,
        queueCapacity: Int = 500,
        maxEventsPerRequest: Int = 100
    ) -> TelemetryClient {
        TelemetryClient(
            configuration: .init(
                flushInterval: 30,
                batchSize: batchSize,
                queueCapacity: queueCapacity,
                maxEventsPerRequest: maxEventsPerRequest,
                entry: "test_entry",
                environment: "sandbox"
            ),
            transport: transport,
            sleep: clock.sleep,
            lifecycle: lifecycle
        )
    }

    /// Fires the timer, failing the test rather than waiting when no timer is running.
    private func tick(file: StaticString = #filePath, line: UInt = #line) async {
        let fired = await clock.tick()
        XCTAssertTrue(fired, "no timer was running", file: file, line: line)
    }

    // MARK: - Triggers

    func testAFullBatchIsSentWithoutWaitingForTheTimer() async {
        let client = makeClient(batchSize: 2)
        await client.emit("tokenization.started", properties: ["method": "card"])
        await client.emit("tokenization.succeeded", properties: ["method": "card"])
        await client.settled()

        let batches = await transport.batches
        XCTAssertEqual(batches.map { $0.map(\.event) }, [["tokenization.started", "tokenization.succeeded"]])
    }

    func testShortOfAFullBatchNothingIsSentUntilTheTimerFires() async {
        let client = makeClient(batchSize: 5)
        await client.emit("e1")
        await client.emit("e2")
        await client.settled()
        let beforeTick = await transport.batches
        XCTAssertTrue(beforeTick.isEmpty)

        await tick()
        await client.settled()

        let batches = await transport.batches
        XCTAssertEqual(batches.map { $0.map(\.event) }, [["e1", "e2"]])
    }

    func testTheTimerKeepsFiringAfterABatchIsRefused() async {
        let client = makeClient()
        await transport.refuse(true)
        await client.emit("first")
        await tick()
        await client.settled()
        await transport.refuse(false)
        await client.emit("second")

        await tick()
        await client.settled()

        let batches = await transport.batches
        XCTAssertEqual(batches.map { $0.map(\.event) }, [["first"], ["second"]])
    }

    func testGoingToTheBackgroundSendsEverythingQueuedWithTimeToFinish() async {
        let client = makeClient()
        await client.emit("a")
        await client.emit("b")

        let closed = await lifecycle.background()

        let batches = await transport.batches
        XCTAssertEqual(batches.map { $0.map(\.event) }, [["a", "b"]])
        XCTAssertTrue(closed, "the background time is handed back once the send has ended")
        XCTAssertEqual(lifecycle.closedCount, 1)
    }

    // MARK: - Sent at once

    func testAnEventReportingAFailureShipsWithoutFillingABatch() async {
        let client = makeClient()
        await client.emit("payin.capture.completed", properties: ["outcome": "declined"])
        await client.settled()

        let batches = await transport.batches
        XCTAssertEqual(batches.count, 1)
    }

    func testAnEventWhoseNameMeansFailureLeavesAtOnce() async {
        let client = makeClient()
        await client.emit(TelemetryEventName.ttpAttestationQuotaExhausted, properties: ["code": "429"])
        await client.settled()

        let batches = await transport.batches
        XCTAssertEqual(batches.count, 1)
    }

    func testAnEventReportingSuccessWaitsForItsBatch() async {
        let client = makeClient()
        await client.emit("payin.capture.completed", properties: ["outcome": "approved"])
        await client.emit("ttp.initialize.succeeded", properties: ["outcome": "succeeded"])
        await client.settled()

        let batches = await transport.batches
        XCTAssertTrue(batches.isEmpty)
    }

    func testAFailureHeldForItsBatchWaitsForIt() async {
        let client = makeClient()
        await client.emit(
            TelemetryEventName.ttpAttestationFailed,
            properties: ["outcome": "failed"],
            occurredAt: Date(),
            waitsForBatch: true
        )
        await client.settled()

        let batches = await transport.batches
        XCTAssertTrue(batches.isEmpty)
    }

    func testAForcedFlushTakesTheQueuedContextWithIt() async {
        let client = makeClient()
        await client.emit("ttp.initialize.started")
        await client.emit(TelemetryEventName.ttpInitializeFailed, properties: ["outcome": "failed"])
        await client.settled()

        let batches = await transport.batches
        XCTAssertEqual(batches.map { $0.map(\.event) }, [["ttp.initialize.started", "ttp.initialize.failed"]])
    }

    func testTheSendAtOnceRule() {
        XCTAssertTrue(TelemetryClient.sendsAtOnce("x", ["outcome": "refused_locally"]))
        XCTAssertTrue(TelemetryClient.sendsAtOnce("x", ["outcome": "something_new"]))
        XCTAssertTrue(TelemetryClient.sendsAtOnce(TelemetryEventName.authTokenFailed, [:]))
        XCTAssertFalse(TelemetryClient.sendsAtOnce("x", ["outcome": "succeeded"]))
        XCTAssertFalse(TelemetryClient.sendsAtOnce("x", ["outcome": "approved"]))
        XCTAssertFalse(TelemetryClient.sendsAtOnce(TelemetryEventName.ttpInitializePending, ["state": "pending_terms"]))
        XCTAssertFalse(
            TelemetryClient.sendsAtOnce(TelemetryEventName.ttpInitializeCancelled, ["duration_ms": "5"]),
            "a dismissed sheet is a choice, not a failure"
        )
        XCTAssertTrue(TelemetryClient.sendsAtOnce(TelemetryEventName.ttpCloseFailed, [:]))
    }

    // MARK: - The bounded queue

    func testWhatTheQueueEvictedIsCarriedByTheNextBatch() async {
        let client = makeClient(queueCapacity: 2)
        await client.emit("a")
        await client.emit("b")
        await client.emit("c")
        await client.flush()

        let batches = await transport.batches
        let counts = await transport.droppedCounts
        XCTAssertEqual(batches.map { $0.map(\.event) }, [["b", "c"]])
        XCTAssertEqual(counts, [1])
    }

    func testABatchThatLostNothingCarriesNoCount() async {
        let client = makeClient()
        await client.emit("a")
        await client.flush()

        let counts = await transport.droppedCounts
        XCTAssertEqual(counts, [0])
    }

    func testACountSurvivesTheBatchThatWasRefused() async {
        let client = makeClient(queueCapacity: 1)
        await client.emit("a")
        await client.emit("b")
        await transport.refuse(true)
        await client.flush()
        await transport.refuse(false)
        await client.emit("c")
        await client.flush()

        let counts = await transport.droppedCounts
        XCTAssertEqual(counts, [1, 1])
    }

    func testAFlushWithNothingToSendDoesNotConsumeTheCount() async {
        let client = makeClient(queueCapacity: 1)
        await client.emit("a")
        await client.emit("b")
        await transport.refuse(true)
        await client.flush()
        await transport.refuse(false)
        await client.flush()
        await client.emit("c")
        await client.flush()

        let counts = await transport.droppedCounts
        XCTAssertEqual(counts, [1, 1], "the refused batch's count survives the empty flush after it")
    }

    func testOneRequestCarriesNoMoreThanOneRequestMay() async {
        let client = makeClient(maxEventsPerRequest: 2)
        for index in 0 ..< 5 {
            await client.emit("e\(index)")
        }
        await client.flush()

        let batches = await transport.batches
        XCTAssertEqual(batches.map(\.count), [2, 2, 1])
    }

    // MARK: - Best effort

    func testAFailedSendNeverReachesTheCaller() async {
        let client = makeClient()
        await transport.refuse(true)
        await client.emit("payin.capture.completed", properties: ["outcome": "failed"])
        await client.flush()

        let buffered = await client.bufferedCount
        XCTAssertEqual(buffered, 0, "a refused batch is dropped, not kept for a retry")
    }

    // MARK: - The event

    func testDeviceIdIsHashedNotRaw() async {
        let client = makeClient()
        await client.setDeviceId("abc-device-123")
        await client.emit("event", properties: [:])
        await client.flush()

        let batches = await transport.batches
        let event = batches.first?.first
        XCTAssertNotNil(event?.deviceIdHash)
        XCTAssertNotEqual(event?.deviceIdHash, "abc-device-123")
        XCTAssertEqual(event?.deviceIdHash?.count, 64, "SHA-256 hex digest is 64 chars")
    }

    func testEnvelopeIncludesVersion() async {
        let client = makeClient()
        await client.emit("x")
        await client.flush()
        let batches = await transport.batches
        let event = batches.first?.first
        XCTAssertEqual(event?.schemaVersion, 1)
        XCTAssertFalse(event?.sdkVersion.isEmpty ?? true)
    }
}

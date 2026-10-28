@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

final class TelemetryClientTests: XCTestCase {
    private let clock = ManualTelemetryClock()
    private let lifecycle = ManualAppLifecycle()
    private let transport = InMemoryTelemetryTransport()
    private let overflow = "sdk.telemetryOverflow"

    private func makeClient(
        batchSize: Int = 20,
        queueCapacity: Int = 500,
        maxEventsPerRequest: Int = 100,
        deviceId: String? = nil,
        queued: [(name: String, properties: [String: String])] = [],
        logger: PayabliLogger = PayabliLogger(category: .telemetry, sink: RecordingLogSink())
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
            lifecycle: lifecycle,
            deviceId: { deviceId },
            queued: queued,
            logger: logger
        )
    }

    /// Records an event that waits for its batch, told apart from the others by `label`.
    private func record(_ client: TelemetryClient, _ label: String) async {
        await client.emit(TelemetryEventName.formPresented, properties: ["step": label])
    }

    /// Records an event whose outcome sends it at once, told apart from the others by `label`.
    private func recordFailure(_ client: TelemetryClient, _ label: String, outcome: String) async {
        await client.emit(TelemetryEventName.payinCaptureCompleted, properties: ["outcome": outcome, "origin": label])
    }

    /// Fires the timer, failing the test rather than waiting when no timer is running.
    private func tick(file: StaticString = #filePath, line: UInt = #line) async {
        let fired = await clock.tick()
        XCTAssertTrue(fired, "no timer was running", file: file, line: line)
    }

    // MARK: - Triggers

    func testAFullBatchIsSentWithoutWaitingForTheTimer() async {
        let client = makeClient(batchSize: 2)
        await client.emit("form.presented")
        await client.emit("ttp.initialize.started")
        await client.settled()

        let batches = await transport.batches
        XCTAssertEqual(batches.map { $0.map(\.label) }, [["form.presented", "ttp.initialize.started"]])
    }

    func testShortOfAFullBatchNothingIsSentUntilTheTimerFires() async {
        let client = makeClient(batchSize: 5)
        await record(client, "e1")
        await record(client, "e2")
        await client.settled()
        let beforeTick = await transport.batches
        XCTAssertTrue(beforeTick.isEmpty)

        await tick()
        await client.settled()

        let batches = await transport.batches
        XCTAssertEqual(batches.map { $0.map(\.label) }, [["e1", "e2"]])
    }

    func testTheTimerKeepsFiringAfterABatchIsRefused() async {
        let client = makeClient()
        await transport.refuse(true)
        await record(client, "first")
        await tick()
        await client.settled()
        await transport.refuse(false)
        await record(client, "second")

        await tick()
        await client.settled()

        let batches = await transport.batches
        XCTAssertEqual(batches.map { $0.map(\.label) }, [["first"], ["first", "second"]])
    }

    func testDeliveryListensForBackgroundingOnceTheFirstEventIsRecorded() async {
        let client = makeClient()

        await record(client, "a")

        XCTAssertTrue(lifecycle.isSubscribed, "subscribed before the first emit returns, not when a task gets to run")
    }

    func testGoingToTheBackgroundSendsEverythingQueuedWithTimeToFinish() async {
        let client = makeClient()
        await record(client, "a")
        await record(client, "b")

        let closed = await lifecycle.background()

        let batches = await transport.batches
        XCTAssertEqual(batches.map { $0.map(\.label) }, [["a", "b"]])
        XCTAssertTrue(closed, "the background time is handed back once the send has ended")
        XCTAssertEqual(lifecycle.closedCount, 1)
    }

    func testOverlappingTriggersRunOneSendAtATimeAndLoseNothing() async {
        let gated = GatedTelemetryTransport()
        let client = TelemetryClient(
            configuration: .init(entry: "test_entry", environment: "sandbox"),
            transport: gated,
            sleep: clock.sleep,
            lifecycle: lifecycle,
            deviceId: { nil },
            queued: []
        )
        await recordFailure(client, "a", outcome: "failed")
        await gated.untilHeld()

        await record(client, "b")
        await tick()
        await recordFailure(client, "c", outcome: "declined")
        let backgrounded = Task { await lifecycle.background() }
        XCTAssertEqual(lifecycle.closedCount, 0, "the background time stays open while a send is held")
        await gated.open()
        let closed = await backgrounded.value
        await client.settled()

        let sent = await gated.sent.flatMap { $0 }.map(\.label)
        let mostAtOnce = await gated.mostAtOnce
        XCTAssertEqual(sent, ["a", "b", "c"])
        XCTAssertEqual(mostAtOnce, 1)
        XCTAssertTrue(closed)
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
        await client.emit("payin.void.completed", properties: ["outcome": "succeeded"])
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
        XCTAssertEqual(batches.map { $0.map(\.label) }, [["ttp.initialize.started", "ttp.initialize.failed"]])
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

    // MARK: - The catalog gate

    func testAKeyTheEventDoesNotDeclareIsNotQueued() async {
        let client = makeClient()
        await client.emit(
            TelemetryEventName.payinCaptureCompleted,
            properties: ["outcome": "approved", "holder": "undeclared"]
        )

        let queued = await client.queuedEvents
        XCTAssertEqual(queued.map(\.properties), [["outcome": "approved"]])
    }

    func testAnEventTheCatalogDoesNotNameIsNotQueued() async {
        let client = makeClient()
        await client.emit("payin.cardNumber.entered", properties: ["outcome": "failed"])
        await client.settled()

        let buffered = await client.bufferedCount
        let batches = await transport.batches
        XCTAssertEqual(buffered, 0)
        XCTAssertTrue(batches.isEmpty, "a dropped event asks for no send")
    }

    func testWhatWasRecordedBeforeTheClientStartedPassesTheSameGate() async {
        let client = makeClient(queued: [
            (TelemetryEventName.sdkInitialized, ["state": "ready", "holder": "undeclared"]),
            ("payin.cardNumber.entered", [:])
        ])

        let queued = await client.queuedEvents
        XCTAssertEqual(queued.map(\.event), [TelemetryEventName.sdkInitialized])
        XCTAssertEqual(queued.map(\.properties), [["state": "ready"]])
    }

    func testADeclaredValueThatCannotBeReportedDropsItsPairAndKeepsTheRest() async {
        let client = makeClient()
        await client.emit(TelemetryEventName.payinCaptureCompleted, properties: [
            "outcome": "approved",
            "code": "",
            "origin": String(repeating: "o", count: 257),
            "failure_type": "Caf\u{E9}Error",
            "duration_ms": "12\n",
            "method": String(repeating: "m", count: 256)
        ])

        let queued = await client.queuedEvents
        XCTAssertEqual(
            queued.map(\.properties),
            [["outcome": "approved", "method": String(repeating: "m", count: 256)]],
            "empty, too long and non-printable values go; a value of exactly 256 stays"
        )
    }

    func testAnOutcomeTheEventDoesNotDeclareDoesNotSendItAtOnce() async {
        let client = makeClient()
        await client.emit(TelemetryEventName.ttpInitializeSucceeded, properties: ["outcome": "failed"])
        await client.settled()

        let batches = await transport.batches
        XCTAssertTrue(batches.isEmpty)
    }

    // MARK: - The bounded queue

    func testWhatTheQueueEvictedArrivesAsOneOverflowEventLastInTheNextBatch() async {
        let client = makeClient(queueCapacity: 2, deviceId: "0f8d2a1c4b6e4a2f9c3d5e7f8a9b0c1d")
        await record(client, "a")
        await record(client, "b")
        await record(client, "c")
        await client.flush()

        let batches = await transport.batches
        XCTAssertEqual(batches.map { $0.map(\.label) }, [["b", "c", overflow]])
        let event = batches.first?.last
        XCTAssertEqual(event?.properties, ["dropped": "1"])
        XCTAssertEqual(event?.entry, "test_entry")
        XCTAssertEqual(event?.deviceIdHash, "0f8d2a1c4b6e4a2f9c3d5e7f8a9b0c1d")
    }

    func testABatchThatLostNothingCarriesNoOverflowEvent() async {
        let client = makeClient()
        await record(client, "a")
        await client.flush()

        let batches = await transport.batches
        XCTAssertEqual(batches.map { $0.map(\.label) }, [["a"]])
    }

    func testARefusedBatchGoesBackWithoutItsOverflowEventAndTheNextCarriesTheRunningTotal() async {
        let client = makeClient(queueCapacity: 2)
        await record(client, "a")
        await record(client, "b")
        await record(client, "c")
        await transport.refuse(true)
        await client.flush()
        await transport.refuse(false)
        await record(client, "d")
        await client.flush()

        let batches = await transport.batches
        XCTAssertEqual(
            batches.map { $0.map(\.label) },
            [["b", "c", overflow], ["c", "d", overflow]],
            "the refused batch went back without its overflow event, and b was evicted from it"
        )
        XCTAssertEqual(batches.map { $0.last?.properties["dropped"] }, ["1", "2"])
    }

    func testAFlushWithNothingToSendDoesNotConsumeTheCount() async {
        let client = makeClient(queueCapacity: 1)
        await record(client, "a")
        await record(client, "b")
        await transport.discard(true)
        await client.flush()
        await transport.discard(false)
        await client.flush()
        await record(client, "c")
        await client.flush()

        let batches = await transport.batches
        XCTAssertEqual(batches.map { $0.map(\.label) }, [["b", overflow], ["c", overflow]])
        XCTAssertEqual(
            batches.map { $0.last?.properties["dropped"] },
            ["1", "1"],
            "the discarded batch's count survives the empty flush after it"
        )
    }

    func testWithACountWaitingAFullRequestCarries99EventsAndTheOverflowEventLast() async {
        let client = makeClient(batchSize: 600)
        for index in 0 ... 500 {
            await record(client, "e\(index)")
        }
        await client.flush()

        let batches = await transport.batches
        XCTAssertEqual(batches.first?.count, 100)
        XCTAssertEqual(batches.first?.last?.event, overflow)
        XCTAssertEqual(batches.first?.dropLast().map(\.label), (1 ... 99).map { "e\($0)" })
        XCTAssertLessThanOrEqual(batches.map(\.count).max() ?? 0, 100, "no request carries more than 100")
    }

    func testOneSignalDrainsAFullQueueAndItsOverflowEvent() async {
        let client = makeClient(batchSize: 600)
        for index in 0 ... 500 {
            await record(client, "e\(index)")
        }
        await client.flush()

        let events = await transport.batches.flatMap { $0 }
        XCTAssertEqual(events.filter { $0.event != overflow }.map(\.label), (1 ... 500).map { "e\($0)" })
        XCTAssertEqual(events.filter { $0.event == overflow }.count, 1)
        let buffered = await client.bufferedCount
        XCTAssertEqual(buffered, 0, "one signal sends everything that was waiting")
    }

    func testOneSignalDrainsEverythingWhenEachRequestIsDiscarded() async {
        let client = makeClient(batchSize: 600)
        for index in 0 ... 500 {
            await record(client, "e\(index)")
        }
        await transport.discard(true)
        await client.flush()

        let batches = await transport.batches
        XCTAssertEqual(
            batches.map { $0.last?.event },
            Array(repeating: overflow, count: batches.count),
            "each discarded request gives its count back, so every request carries the event"
        )
        XCTAssertEqual(batches.flatMap { $0 }.filter { $0.event != overflow }.count, 500)
        let buffered = await client.bufferedCount
        XCTAssertEqual(buffered, 0, "one signal sends everything that was waiting")
    }

    func testOneRequestCarriesNoMoreThanOneRequestMay() async {
        let client = makeClient(maxEventsPerRequest: 2)
        for index in 0 ..< 5 {
            await record(client, "e\(index)")
        }
        await client.flush()

        let batches = await transport.batches
        XCTAssertEqual(batches.map(\.count), [2, 2, 1])
    }

    // MARK: - A batch that could not be sent

    func testARefusedBatchIsQueuedAgainInOrderAndTheNextFlushSendsIt() async {
        let client = makeClient()
        await transport.refuse(true)
        await record(client, "first")
        await record(client, "second")
        await client.flush()
        await transport.refuse(false)

        await tick()
        await client.settled()

        let batches = await transport.batches
        XCTAssertEqual(
            batches.map { $0.map(\.label) },
            [["first", "second"], ["first", "second"]],
            "the refused batch goes back to the front and the next flush sends it"
        )
        let buffered = await client.bufferedCount
        XCTAssertEqual(buffered, 0)
    }

    func testAFailedSendMakesNoRequestUntilTheNextFlush() async {
        let client = makeClient(batchSize: 600)
        for index in 0 ..< 250 {
            await record(client, "e\(index)")
        }
        await transport.refuse(true)
        await client.flush()

        let afterFailure = await transport.batches
        XCTAssertEqual(afterFailure.count, 1, "a failed send starts no loop")

        await transport.refuse(false)
        await tick()
        await client.settled()

        let batches = await transport.batches
        XCTAssertEqual(batches.map(\.count), [100, 100, 100, 50], "the next flush drains what waited")
    }

    func testADiscardedBatchIsNotQueuedAgain() async {
        let client = makeClient()
        await transport.discard(true)
        await record(client, "only")
        await client.flush()

        let buffered = await client.bufferedCount
        XCTAssertEqual(buffered, 0, "a discarded batch is dropped, not kept for a retry")

        await transport.discard(false)
        await tick()
        await client.settled()

        let batches = await transport.batches
        XCTAssertEqual(batches.count, 1, "nothing was left for the next flush")
    }

    func testARefusedBatchEvictedOnItsWayBackKeepsEveryLossInTheCount() async {
        let gated = GatedTelemetryTransport()
        let client = TelemetryClient(
            configuration: .init(
                batchSize: 5,
                queueCapacity: 3,
                entry: "test_entry",
                environment: "sandbox"
            ),
            transport: gated,
            sleep: clock.sleep,
            lifecycle: lifecycle,
            deviceId: { nil },
            queued: []
        )
        await gated.reply(with: .kept)
        await record(client, "lost")
        await record(client, "first")
        await record(client, "second")
        await recordFailure(client, "third", outcome: "failed")
        await gated.untilHeld()
        await record(client, "fourth")
        await record(client, "fifth")
        await record(client, "sixth")
        await gated.open()
        await client.settled()
        await gated.reply(with: .delivered)

        await tick()
        await client.settled()

        let sent = await gated.sent
        XCTAssertEqual(
            sent.map { $0.map(\.label) },
            [["first", "second", "third", overflow], ["fourth", "fifth", "sixth", overflow]]
        )
        XCTAssertEqual(
            sent.map { $0.last?.properties["dropped"] },
            ["1", "4"],
            "the refused batch's count, plus its three events evicted on the way back"
        )
    }

    // MARK: - When a batch fills

    func testWithSendsRefused40EventsOfferedOneAtATimeMakeTwoSendAttempts() async {
        let client = makeClient()
        await transport.refuse(true)
        for index in 0 ..< 40 {
            await record(client, "e\(index)")
            await client.settled()
        }

        let attempts = await transport.batches
        XCTAssertEqual(attempts.map(\.count), [20, 40], "a put-back batch does not count toward the next twenty")

        await transport.refuse(false)
        await tick()
        await client.settled()

        let batches = await transport.batches
        XCTAssertEqual(batches.last?.map(\.label), (0 ..< 40).map { "e\($0)" })
    }

    func testTwentyNewEventsAfterASuccessfulSendStillSendAtOnce() async {
        let client = makeClient()
        for index in 0 ..< 40 {
            await record(client, "e\(index)")
            await client.settled()
        }

        let batches = await transport.batches
        XCTAssertEqual(batches.map(\.count), [20, 20])
    }

    // MARK: - Best effort

    func testAFailedSendNeverReachesTheCaller() async {
        let client = makeClient()
        await transport.refuse(true)
        await client.emit("payin.capture.completed", properties: ["outcome": "failed"])
        await client.flush()

        let buffered = await client.bufferedCount
        XCTAssertEqual(buffered, 1, "a refused batch is kept for a later flush, never raised to the caller")
    }

    // MARK: - The event

    func testEveryEventCarriesTheDeviceIdentifierAsItIs() async {
        let identifier = "0f8d2a1c4b6e4a2f9c3d5e7f8a9b0c1d"
        let client = makeClient(deviceId: identifier, queued: [("sdk.initialized", ["state": "ready"])])
        await client.emit("ttp.initialize.started")
        await client.flush()

        let events = await transport.batches.flatMap { $0 }
        XCTAssertEqual(events.map(\.deviceIdHash), [identifier, identifier], "not hashed again")
    }

    func testADeviceThatCannotBeIdentifiedSendsNoIdentifier() async {
        let client = makeClient(deviceId: "")
        await record(client, "x")
        await client.flush()

        let events = await transport.batches.flatMap { $0 }
        XCTAssertEqual(events.count, 1)
        XCTAssertNil(events.first?.deviceIdHash)
    }

    func testWhatWasQueuedAtConstructionLeavesFirst() async {
        let client = makeClient(queued: [("sdk.initialized", ["state": "ready"])])
        await client.emit("ttp.initialize.started")
        await client.flush()

        let batches = await transport.batches
        XCTAssertEqual(batches.map { $0.map(\.label) }, [["sdk.initialized", "ttp.initialize.started"]])
        XCTAssertEqual(batches.first?.first?.properties, ["state": "ready"])
    }

    func testWhatWasQueuedAtConstructionLeavesOnTheTimerWithNothingElseRecorded() async {
        let client = makeClient(queued: [("sdk.initialized", ["state": "ready"])])

        await clock.tick()
        await client.settled()

        let batches = await transport.batches
        XCTAssertEqual(batches.map { $0.map(\.label) }, [["sdk.initialized"]])
    }

    func testEnvelopeIncludesVersion() async {
        let client = makeClient()
        await record(client, "x")
        await client.flush()
        let batches = await transport.batches
        let event = batches.first?.first
        XCTAssertEqual(event?.schemaVersion, 1)
        XCTAssertFalse(event?.sdkVersion.isEmpty ?? true)
    }
}

/// Holds every send until opened, and records how many were in flight at once.
private actor GatedTelemetryTransport: TelemetryTransport {
    private(set) var sent: [[TelemetryEvent]] = []
    private(set) var mostAtOnce = 0
    private var active = 0
    private var isOpen = false
    private var outcome: TelemetrySendOutcome = .delivered
    private var gates: [CheckedContinuation<Void, Never>] = []
    private var heldWaiters: [CheckedContinuation<Void, Never>] = []

    /// Makes every released send answer with this outcome.
    func reply(with outcome: TelemetrySendOutcome) {
        self.outcome = outcome
    }

    func send(_ batch: [TelemetryEvent]) async -> TelemetrySendOutcome {
        active += 1
        mostAtOnce = max(mostAtOnce, active)
        if !isOpen {
            await withCheckedContinuation { gate in
                gates.append(gate)
                heldWaiters.forEach { $0.resume() }
                heldWaiters.removeAll()
            }
        }
        sent.append(batch)
        active -= 1
        return outcome
    }

    /// Returns once a send is held.
    func untilHeld() async {
        guard gates.isEmpty else { return }
        await withCheckedContinuation { heldWaiters.append($0) }
    }

    /// Lets every held send through, and every later one without holding it.
    func open() {
        isOpen = true
        gates.forEach { $0.resume() }
        gates.removeAll()
    }
}

private extension TelemetryEvent {
    /// The label a test recorded the event under, or its name for an event recorded by name.
    var label: String {
        properties["step"] ?? properties["origin"] ?? event
    }
}

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

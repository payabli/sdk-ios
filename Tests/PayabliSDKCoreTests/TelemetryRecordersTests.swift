@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// The process's one recorder: a record reaches whatever channel is installed when it is made, and nothing when none is.
final class TelemetryRecordersTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TelemetryRecorders.clear()
    }

    override func tearDown() {
        TelemetryRecorders.clear()
        super.tearDown()
    }

    func testWithNothingInstalledARecordBuildsNoProperties() async {
        let built = PropertyBuilds()

        TelemetryRecorders.record(TelemetryEventName.ttpInitializeStarted, properties: built.next())

        await TelemetryRecorders.settled()
        XCTAssertEqual(built.value, 0, "with nothing listening the properties are never built")
    }

    func testARecordReachesTheInstalledChannel() async {
        let transport = InMemoryTelemetryTransport()
        TelemetryRecorders.install(Self.client(entry: "e", transport: transport))

        TelemetryRecorders.record(TelemetryEventName.ttpInitializeStarted)

        let events = await sent(transport)
        XCTAssertEqual(events.map(\.event), [TelemetryEventName.ttpInitializeStarted])
    }

    func testARecordAfterAReinstallReachesOnlyTheNewChannel() async {
        let old = InMemoryTelemetryTransport()
        let new = InMemoryTelemetryTransport()
        let oldClient = Self.client(entry: "e", transport: old)
        TelemetryRecorders.install(oldClient)
        TelemetryRecorders.install(Self.client(entry: "e", transport: new))

        TelemetryRecorders.record(TelemetryEventName.ttpInitializeStarted)

        await oldClient.flush()
        let reachedOld = await old.drainBatches().flatMap { $0 }
        XCTAssertEqual(reachedOld.map(\.event), [])
        let reachedNew = await sent(new)
        XCTAssertEqual(reachedNew.map(\.event), [TelemetryEventName.ttpInitializeStarted])
    }

    func testWorkFromAReplacedSessionOnTheSameEntryPointLeavesOnTheNewChannelUnderItsOwnSession() async {
        let transport = InMemoryTelemetryTransport()
        let started = Self.client(entry: "e", transport: InMemoryTelemetryTransport())
        let installed = Self.client(entry: "e", transport: transport)
        TelemetryRecorders.install(installed)

        TelemetryRecorders.recordFor(started.context, TelemetryEventName.ttpInitializeStarted)

        let events = await sent(transport)
        XCTAssertEqual(events.map(\.event), [TelemetryEventName.ttpInitializeStarted])
        XCTAssertEqual(events.map(\.sessionId), [started.sessionId])
        XCTAssertNotEqual(started.sessionId, installed.sessionId)
    }

    func testWorkFromAReplacedSessionOnAnotherEntryPointIsDropped() async {
        let transport = InMemoryTelemetryTransport()
        let started = Self.client(entry: "first", transport: InMemoryTelemetryTransport())
        TelemetryRecorders.install(Self.client(entry: "second", transport: transport))

        TelemetryRecorders.recordFor(started.context, TelemetryEventName.ttpInitializeStarted)

        let events = await sent(transport)
        XCTAssertEqual(events.map(\.event), [], "a record for another entry point is never delivered on this channel")
    }

    func testARecordDeliveredAfterAReinstallLeavesOnTheNewChannelUnderTheSessionItWasMadeUnder() async {
        let gate = BlockingDeviceId()
        let first = TelemetryClient(
            configuration: .init(entry: "e", environment: "sandbox"),
            transport: InMemoryTelemetryTransport(),
            sleep: ManualTelemetryClock().sleep,
            lifecycle: ManualAppLifecycle(),
            deviceId: gate.read,
            queued: []
        )
        let latest = InMemoryTelemetryTransport()
        let latestClient = Self.client(entry: "e", transport: latest)
        TelemetryRecorders.install(first)
        TelemetryRecorders.record(TelemetryEventName.ttpInitializeFailed, properties: ["outcome": "failed"])
        let reading = await gate.waitUntilReading()
        XCTAssertTrue(reading, "the failure's send never started")
        TelemetryRecorders.record(TelemetryEventName.ttpInitializeStarted)
        TelemetryRecorders.record(TelemetryEventName.ttpAttestationStarted)

        TelemetryRecorders.install(latestClient)
        gate.release()

        let events = await sent(latest)
        XCTAssertEqual(events.last?.event, TelemetryEventName.ttpAttestationStarted, "\(events.map(\.event))")
        XCTAssertEqual(Set(events.map(\.sessionId)), [first.sessionId])
    }

    func testAFlushWaitingOnADeliveryWhileAChannelIsInstalledSendsOnTheNewChannel() async throws {
        let gate = BlockingDeviceId()
        let first = TelemetryClient(
            configuration: .init(entry: "e", environment: "sandbox"),
            transport: InMemoryTelemetryTransport(),
            sleep: ManualTelemetryClock().sleep,
            lifecycle: ManualAppLifecycle(),
            deviceId: gate.read,
            queued: []
        )
        let next = InMemoryTelemetryTransport()
        TelemetryRecorders.install(first)
        TelemetryRecorders.record(TelemetryEventName.ttpInitializeFailed, properties: ["outcome": "failed"])
        let reading = await gate.waitUntilReading()
        XCTAssertTrue(reading, "the failure's send never started")
        TelemetryRecorders.record(TelemetryEventName.ttpInitializeStarted)
        TelemetryRecorders.record(TelemetryEventName.ttpAttestationStarted)
        let flushing = Task { await TelemetryRecorders.flush() }
        try await Task.sleep(for: .milliseconds(100))

        TelemetryRecorders.install(Self.client(entry: "e", transport: next))
        gate.release()
        await flushing.value

        let events = await next.drainBatches().flatMap { $0 }
        XCTAssertEqual(events.last?.event, TelemetryEventName.ttpAttestationStarted, "\(events.map(\.event))")
    }

    func testAChannelIsUnreachableOnlyOnceReplacedAndEveryRecordMadeBeforeHasArrived() async throws {
        let gate = BlockingDeviceId()
        let first = TelemetryClient(
            configuration: .init(entry: "e", environment: "sandbox"),
            transport: InMemoryTelemetryTransport(),
            sleep: ManualTelemetryClock().sleep,
            lifecycle: ManualAppLifecycle(),
            deviceId: gate.read,
            queued: []
        )
        TelemetryRecorders.install(first)
        let retired = Retired()
        let waiting = Task {
            await TelemetryRecorders.unreachable(first)
            await retired.mark()
        }
        try await Task.sleep(for: .milliseconds(100))
        let whileInstalled = await retired.value
        TelemetryRecorders.record(TelemetryEventName.ttpInitializeFailed, properties: ["outcome": "failed"])
        let reading = await gate.waitUntilReading()
        XCTAssertTrue(reading, "the failure's send never started")
        let builder = BlockingBuilder()
        let recording = await recordWhileBuilding(builder)

        TelemetryRecorders.install(Self.client(entry: "e", transport: InMemoryTelemetryTransport()))
        try await Task.sleep(for: .milliseconds(100))
        let whileARecordWasOnItsWay = await retired.value
        builder.release()
        await recording.value
        gate.release()
        await waiting.value

        XCTAssertFalse(whileInstalled, "installed, so a record can still reach it")
        XCTAssertFalse(whileARecordWasOnItsWay, "a record made while it was installed had not arrived")
        let arrived = await retired.value
        XCTAssertTrue(arrived)
    }

    func testRecordsInFlightAcrossTwoReplacementsArriveOnceAndNeitherReplacedChannelRetiresEarly() async throws {
        let gate = BlockingDeviceId()
        let firstTransport = InMemoryTelemetryTransport()
        let first = TelemetryClient(
            configuration: .init(entry: "e", environment: "sandbox"),
            transport: firstTransport,
            sleep: ManualTelemetryClock().sleep,
            lifecycle: ManualAppLifecycle(),
            deviceId: gate.read,
            queued: []
        )
        let secondTransport = InMemoryTelemetryTransport()
        let second = Self.client(entry: "e", transport: secondTransport)
        let latestTransport = InMemoryTelemetryTransport()
        let latest = Self.client(entry: "e", transport: latestTransport)
        TelemetryRecorders.install(first)
        let firstRetired = Retired()
        let secondRetired = Retired()
        let waitingOnFirst = Task {
            await TelemetryRecorders.unreachable(first)
            await firstRetired.mark()
        }
        TelemetryRecorders.record(TelemetryEventName.ttpInitializeFailed, properties: ["outcome": "failed"])
        let reading = await gate.waitUntilReading()
        XCTAssertTrue(reading, "the failure's send never started")
        let builder = BlockingBuilder()
        let recording = await recordWhileBuilding(builder)
        TelemetryRecorders.install(second)
        let waitingOnSecond = Task {
            await TelemetryRecorders.unreachable(second)
            await secondRetired.mark()
        }
        TelemetryRecorders.record(TelemetryEventName.ttpAttestationStarted)
        TelemetryRecorders.install(latest)
        TelemetryRecorders.record(TelemetryEventName.ttpAttestationSucceeded)
        try await Task.sleep(for: .milliseconds(100))
        let firstWhileOnItsWay = await firstRetired.value
        let secondWhileOnItsWay = await secondRetired.value

        builder.release()
        await recording.value
        gate.release()
        await waitingOnFirst.value
        await waitingOnSecond.value

        XCTAssertFalse(firstWhileOnItsWay, "a record made while the first channel was installed had not arrived")
        XCTAssertFalse(secondWhileOnItsWay, "a record made while the second channel was installed had not arrived")
        await first.flush()
        let onFirst = await firstTransport.drainBatches().flatMap { $0 }.map(\.event)
        XCTAssertEqual(onFirst, [TelemetryEventName.ttpInitializeFailed])
        await second.flush()
        let onSecond = await secondTransport.drainBatches().flatMap { $0 }
        XCTAssertEqual(onSecond.map(\.event), [])
        let onLatest = await sent(latestTransport)
        let attestation = [TelemetryEventName.ttpAttestationStarted, TelemetryEventName.ttpAttestationSucceeded]
        XCTAssertEqual(onLatest.map(\.event), [TelemetryEventName.ttpInitializeStarted] + attestation)
        XCTAssertEqual(onLatest.map(\.sessionId), [first.sessionId, second.sessionId, latest.sessionId])
    }

    func testAChannelClearedWhileARecordBuildsItsPropertiesIsUnreachableOnlyOnceThatRecordArrives() async throws {
        let transport = InMemoryTelemetryTransport()
        let client = Self.client(entry: "e", transport: transport)
        TelemetryRecorders.install(client)
        let builder = BlockingBuilder()
        let recording = Task.detached {
            TelemetryRecorders.record(TelemetryEventName.ttpInitializeStarted, properties: builder.build())
        }
        let building = await builder.waitUntilBuilding()
        XCTAssertTrue(building, "the properties were never built")
        TelemetryRecorders.clear()
        let retired = Retired()
        let waiting = Task {
            await TelemetryRecorders.unreachable(client)
            await retired.mark()
        }
        try await Task.sleep(for: .milliseconds(100))
        let whileBuilding = await retired.value

        builder.release()
        await recording.value
        await waiting.value

        XCTAssertFalse(whileBuilding, "a record made while it was installed was still being built")
        await client.flush()
        let events = await transport.drainBatches().flatMap { $0 }
        XCTAssertEqual(events.map(\.event), [TelemetryEventName.ttpInitializeStarted])
    }

    func testRecordsFromTwoCallersArriveInTheOrderTheyWereMade() async {
        let transport = InMemoryTelemetryTransport()
        let client = Self.client(entry: "e", transport: transport)
        TelemetryRecorders.install(client)
        let names = [
            TelemetryEventName.ttpInitializeStarted,
            TelemetryEventName.ttpAttestationStarted,
            TelemetryEventName.ttpAttestationSucceeded,
            TelemetryEventName.ttpInitializeSucceeded
        ]

        for (index, name) in names.enumerated() {
            if index.isMultiple(of: 2) {
                TelemetryRecorders.record(name)
            } else {
                TelemetryRecorders.recordFor(client.context, name)
            }
        }

        let events = await sent(transport)
        XCTAssertEqual(events.map(\.event), names)
    }

    // MARK: - Fixtures

    private static func client(entry: String, transport: InMemoryTelemetryTransport) -> TelemetryClient {
        TelemetryClient(
            configuration: .init(entry: entry, environment: "sandbox"),
            transport: transport,
            sleep: ManualTelemetryClock().sleep,
            lifecycle: ManualAppLifecycle(),
            deviceId: { nil },
            queued: []
        )
    }

    private func sent(_ transport: InMemoryTelemetryTransport) async -> [TelemetryEvent] {
        await TelemetryRecorders.settled()
        await TelemetryRecorders.flush()
        return await transport.drainBatches().flatMap { $0 }
    }
}

/// Counts how many times the property builder ran.
private final class PropertyBuilds: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func next() -> [String: String] {
        lock.withLock { count += 1 }
        return [:]
    }
}

/// Records an event on another thread, and returns once its properties are being built and `builder` holds them.
///
/// - Parameter builder: the gate the properties wait on.
/// - Returns: the recording, which ends once `builder` is released.
private func recordWhileBuilding(_ builder: BlockingBuilder) async -> Task<Void, Never> {
    let recording = Task.detached {
        TelemetryRecorders.record(TelemetryEventName.ttpInitializeStarted, properties: builder.build())
    }
    let building = await builder.waitUntilBuilding()
    XCTAssertTrue(building, "the properties were never built")
    return recording
}

/// A device id read that blocks its client's actor until released, so a delivery to that client waits behind it.
private final class BlockingDeviceId: @unchecked Sendable {
    private let released = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var open = false
    private var started = false

    var read: @Sendable () -> String? {
        { [self] in
            lock.withLock { started = true }
            if !lock.withLock({ open }) {
                _ = released.wait(timeout: .now() + 5)
            }
            return nil
        }
    }

    /// - Returns: whether a read began within five seconds.
    func waitUntilReading() async -> Bool {
        for _ in 0 ..< 500 {
            if lock.withLock({ started }) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func release() {
        lock.withLock { open = true }
        released.signal()
    }
}

/// Whether a wait has returned.
private actor Retired {
    private(set) var value = false

    func mark() {
        value = true
    }
}

/// A properties builder that blocks until released, so a record stays between reading the channel and being queued.
private final class BlockingBuilder: @unchecked Sendable {
    private let released = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var started = false

    func build() -> [String: String] {
        lock.withLock { started = true }
        _ = released.wait(timeout: .now() + 5)
        return ["outcome": "started"]
    }

    /// - Returns: whether the builder began within five seconds.
    func waitUntilBuilding() async -> Bool {
        for _ in 0 ..< 500 {
            if lock.withLock({ started }) {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return false
    }

    func release() {
        released.signal()
    }
}

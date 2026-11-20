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

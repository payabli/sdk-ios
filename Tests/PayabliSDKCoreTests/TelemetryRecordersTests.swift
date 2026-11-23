@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// The process's one recorder: a record is appended to whatever channel is installed when it is made, before the call
/// returns, and to nothing when none is.
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

    func testARecordIsInTheInstalledQueueWhenRecordReturns() {
        let client = Self.client(entry: "e", transport: InMemoryTelemetryTransport())
        TelemetryRecorders.install(client)

        TelemetryRecorders.record(TelemetryEventName.ttpInitializeStarted)

        XCTAssertEqual(client.queuedEvents.map(\.event), [TelemetryEventName.ttpInitializeStarted])
    }

    func testARecordMadeBeforeAReinstallStaysOnTheChannelItWasMadeOn() {
        let first = Self.client(entry: "e", transport: InMemoryTelemetryTransport())
        let second = Self.client(entry: "e", transport: InMemoryTelemetryTransport())
        TelemetryRecorders.install(first)

        TelemetryRecorders.record(TelemetryEventName.ttpInitializeStarted)
        TelemetryRecorders.install(second)

        XCTAssertEqual(first.queuedEvents.map(\.event), [TelemetryEventName.ttpInitializeStarted])
        XCTAssertEqual(second.queuedEvents.map(\.event), [])
    }

    func testAChannelIsReplacedOnlyOnceAnotherIsInstalled() async {
        let first = Self.client(entry: "e", transport: InMemoryTelemetryTransport())
        TelemetryRecorders.install(first)
        let waiting = Task { await TelemetryRecorders.replaced(first) }

        TelemetryRecorders.install(Self.client(entry: "e", transport: InMemoryTelemetryTransport()))

        await waiting.value
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

    func testARecordBuildingItsPropertiesAcrossAReplacementArrivesUnderTheSessionItWasMadeIn() async throws {
        let first = Self.client(entry: "e", transport: InMemoryTelemetryTransport())
        TelemetryRecorders.install(first)
        let builder = BlockingBuilder()
        let recording = await recordWhileBuilding(builder) {
            TelemetryRecorders.record(TelemetryEventName.ttpInitializeStarted, properties: builder.build())
        }

        let transport = InMemoryTelemetryTransport()
        TelemetryRecorders.install(Self.client(entry: "e", transport: transport, replacing: first))
        // Room for a hand-over that does not wait for the record to close the replaced channel's queue.
        try await Task.sleep(for: .milliseconds(100))
        builder.release()
        await recording.value

        let events = await sent(transport)
        XCTAssertEqual(events.map(\.event), [TelemetryEventName.ttpInitializeStarted])
        XCTAssertEqual(events.map(\.sessionId), [first.sessionId])
    }

    func testARecordForASessionBuildingItsPropertiesAcrossAReplacementArrivesUnderThatSession() async throws {
        let started = Self.client(entry: "e", transport: InMemoryTelemetryTransport())
        let first = Self.client(entry: "e", transport: InMemoryTelemetryTransport())
        TelemetryRecorders.install(first)
        let builder = BlockingBuilder()
        let recording = await recordWhileBuilding(builder) {
            TelemetryRecorders.recordFor(
                started.context,
                TelemetryEventName.ttpInitializeStarted,
                properties: builder.build()
            )
        }

        let transport = InMemoryTelemetryTransport()
        TelemetryRecorders.install(Self.client(entry: "e", transport: transport, replacing: first))
        // Room for a hand-over that does not wait for the record to close the replaced channel's queue.
        try await Task.sleep(for: .milliseconds(100))
        builder.release()
        await recording.value

        let events = await sent(transport)
        XCTAssertEqual(events.map(\.event), [TelemetryEventName.ttpInitializeStarted])
        XCTAssertEqual(events.map(\.sessionId), [started.sessionId])
    }

    // MARK: - Fixtures

    private static func client(
        entry: String,
        transport: InMemoryTelemetryTransport,
        replacing predecessor: TelemetryClient? = nil
    ) -> TelemetryClient {
        TelemetryClient(
            configuration: .init(entry: entry, environment: "sandbox"),
            transport: transport,
            sleep: ManualTelemetryClock().sleep,
            lifecycle: ManualAppLifecycle(),
            deviceId: { nil },
            queued: [],
            predecessor: predecessor,
            predecessorReplaced: { await TelemetryRecorders.replaced($0) }
        )
    }

    /// Starts `record` on another thread, and returns once its properties are being built and `builder` holds them.
    ///
    /// - Parameter builder: the gate the properties wait on.
    /// - Parameter record: the record whose properties `builder` builds.
    /// - Returns: the recording, which ends once `builder` is released.
    private func recordWhileBuilding(
        _ builder: BlockingBuilder,
        _ record: @escaping @Sendable () -> Void
    ) async -> Task<Void, Never> {
        let recording = Task.detached { record() }
        let building = await builder.waitUntilBuilding()
        XCTAssertTrue(building, "the properties were never built")
        return recording
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

/// Property building that holds its record until released.
private final class BlockingBuilder: @unchecked Sendable {
    private let released = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var started = false

    func build() -> [String: String] {
        lock.withLock { started = true }
        _ = released.wait(timeout: .now() + 5)
        return [:]
    }

    /// - Returns: whether the building began within five seconds.
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

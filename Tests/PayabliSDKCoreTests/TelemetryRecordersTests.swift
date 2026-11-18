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

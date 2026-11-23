@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

final class TelemetryWakeupTests: XCTestCase {
    let lifecycle = ManualAppLifecycle()
    let transport = InMemoryTelemetryTransport()

    func testASubscriptionNoWatcherReadsEndsWhenClosedAndClosesTheWindowItHolds() async {
        let subscription = BackgroundSubscription(lifecycle)
        subscription.subscribe()
        let windowClosed = lifecycle.post()

        subscription.close()

        let closed = await windowClosed()
        XCTAssertTrue(closed, "a window the subscription held is handed back")
        XCTAssertFalse(lifecycle.isSubscribed)
    }

    func testASubscriptionAskedForAfterCloseIsNeverMade() {
        let subscription = BackgroundSubscription(lifecycle)

        subscription.close()
        subscription.subscribe()
        _ = subscription.consume()

        XCTAssertEqual(lifecycle.subscriptionCount, 0)
    }

    func testARecordAcceptedBeforeAStopLeavesNoSubscriptionBehind() async {
        for retire in [Retire.stop, .handOff] {
            let lifecycle = ManualAppLifecycle()
            let client = makeClient(lifecycle)
            client.record(TelemetryEventName.formValidationError)

            switch retire {
            case .stop: await client.stop()
            case .handOff: _ = await client.handOff()
            }
            await client.settled()

            let ended = await eventually { !lifecycle.isSubscribed }
            XCTAssertTrue(ended, "\(retire): the subscription ends with the client")
        }
    }

    func testRequestsSentWhileOneWaitsToStartJoinIt() async {
        let signals = FlushSignals()
        let gate = Gate()
        let runs = Runs()
        signals.send(flushes: false) { flushes in
            await gate.wait()
            runs.add(flushes)
        }

        for _ in 0 ..< 100 {
            signals.send(flushes: true) { runs.add($0) }
        }
        gate.open()
        await signals.sent()

        XCTAssertLessThanOrEqual(runs.all.count, 2, "one request runs and at most one waits")
        XCTAssertTrue(runs.all.contains(true), "the send asked for is kept")
    }

    private enum Retire {
        case stop
        case handOff
    }

    private func makeClient(_ lifecycle: ManualAppLifecycle) -> TelemetryClient {
        TelemetryClient(
            configuration: .init(entry: "test_entry", environment: "sandbox"),
            transport: transport,
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) },
            lifecycle: lifecycle,
            deviceId: { nil },
            queued: []
        )
    }

    private func eventually(_ condition: () -> Bool) async -> Bool {
        for _ in 0 ..< 200 {
            if condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return condition()
    }
}

private final class Gate: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func wait() async {
        await withCheckedContinuation { continuation in
            let resume = lock.withLock {
                if isOpen {
                    return true
                }
                waiters.append(continuation)
                return false
            }
            if resume {
                continuation.resume()
            }
        }
    }

    func open() {
        let waiting = lock.withLock {
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        waiting.forEach { $0.resume() }
    }
}

private final class Runs: @unchecked Sendable {
    private let lock = NSLock()
    private var flushes: [Bool] = []

    var all: [Bool] {
        lock.withLock { flushes }
    }

    func add(_ value: Bool) {
        lock.withLock { flushes.append(value) }
    }
}

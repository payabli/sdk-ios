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

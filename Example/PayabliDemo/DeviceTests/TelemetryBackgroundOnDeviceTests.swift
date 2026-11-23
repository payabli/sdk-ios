import ObjectiveC
@testable import PayabliSDKCore
import UIKit
import XCTest

/// Telemetry's background tasks, counted where the app's own `UIApplication` begins and ends them. An SPM test bundle
/// has no application to ask for background time, so the package's tests use a stand-in lifecycle.
@MainActor
final class TelemetryBackgroundOnDeviceTests: XCTestCase {
    /// The demo app runs its own session, whose delivery hears the shared center. This one reaches only the client
    /// under test, and the window it opens is still UIKit's.
    private let center = NotificationCenter()

    override func setUp() {
        super.setUp()
        BackgroundTaskLedger.swapIn()
    }

    override func tearDown() {
        BackgroundTaskLedger.swapOut()
        super.tearDown()
    }

    func testABackgroundingDuringASendHoldsItsTaskUntilTheSendEnds() async {
        let transport = GatedTransport()
        let client = makeClient(transport)
        client.record(TelemetryEventName.ttpInitializeStarted)
        await client.settled()

        postBackground()
        let sending = await eventually { await transport.started == 1 }

        XCTAssertTrue(sending, "the backgrounding sends what is queued")
        XCTAssertEqual(BackgroundTaskLedger.open, 1, "the task stays open while the send is in flight")
        await transport.open()
        let ended = await eventually { BackgroundTaskLedger.open == 0 }
        XCTAssertTrue(ended, "the task ends once the send has ended")
        XCTAssertEqual(BackgroundTaskLedger.begun, 1)
        await client.stop()
    }

    func testABackgroundingAfterTheClientIsRetiredLeavesNoTaskOpen() async {
        for retire in [Retire.stop, .handOff] {
            let transport = GatedTransport()
            await transport.open()
            let client = makeClient(transport)
            client.record(TelemetryEventName.ttpInitializeStarted)
            switch retire {
            case .stop: await client.stop()
            case .handOff: _ = await client.handOff()
            }
            await client.settled()

            postBackground()

            let ended = await eventually { BackgroundTaskLedger.open == 0 }
            XCTAssertTrue(ended, "\(retire): no background task outlives the client")
        }
    }

    func testAWindowHeldWhenTheSubscriptionClosesIsEnded() async {
        let subscription = BackgroundSubscription(UIKitAppLifecycle(center: center))
        subscription.subscribe()
        postBackground()
        XCTAssertEqual(BackgroundTaskLedger.open, 1, "the backgrounding asks UIKit for its time before anything reads it")

        subscription.close()

        let ended = await eventually { BackgroundTaskLedger.open == 0 }
        XCTAssertTrue(ended, "closing hands back the time the subscription held")
    }

    private enum Retire {
        case stop
        case handOff
    }

    private func makeClient(_ transport: GatedTransport) -> TelemetryClient {
        TelemetryClient(
            configuration: .init(entry: "device_tests", environment: "sandbox"),
            transport: transport,
            sleep: { _ in try await Task.sleep(for: .seconds(3600)) },
            lifecycle: UIKitAppLifecycle(center: center),
            deviceId: { nil },
            queued: []
        )
    }

    /// Posts the notification UIKit posts as the app leaves the foreground, on the main thread as UIKit does.
    private func postBackground() {
        center.post(name: UIKitAppLifecycle.backgroundNotification, object: UIApplication.shared)
    }

    private func eventually(_ condition: () async -> Bool) async -> Bool {
        for _ in 0 ..< 200 {
            if await condition() {
                return true
            }
            try? await Task.sleep(for: .milliseconds(10))
        }
        return await condition()
    }
}

/// A transport whose sends wait until the test opens it.
private actor GatedTransport: TelemetryTransport {
    private(set) var started = 0
    private var isOpen = false
    private var waiting: [CheckedContinuation<Void, Never>] = []

    func send(_: [TelemetryEvent]) async -> TelemetrySendOutcome {
        started += 1
        if !isOpen {
            await withCheckedContinuation { waiting.append($0) }
        }
        return .delivered
    }

    func open() {
        isOpen = true
        waiting.forEach { $0.resume() }
        waiting = []
    }
}

/// The SDK's background tasks UIKit has begun and not yet ended, counted by exchanging `UIApplication`'s two methods
/// for ones that count and then call the originals.
@MainActor
private enum BackgroundTaskLedger {
    static let name = "PayabliTelemetry"
    private static var tasks: Set<UIBackgroundTaskIdentifier> = []
    private(set) static var begun = 0

    static var open: Int {
        tasks.count
    }

    static func swapIn() {
        tasks = []
        begun = 0
        exchange()
    }

    static func swapOut() {
        exchange()
    }

    static func began(_ task: UIBackgroundTaskIdentifier) {
        begun += 1
        tasks.insert(task)
    }

    static func ended(_ task: UIBackgroundTaskIdentifier) {
        tasks.remove(task)
    }

    private static func exchange() {
        let pairs = [
            (
                #selector(UIApplication.beginBackgroundTask(withName:expirationHandler:)),
                #selector(UIApplication.ledgerBeginBackgroundTask(withName:expirationHandler:))
            ),
            (#selector(UIApplication.endBackgroundTask(_:)), #selector(UIApplication.ledgerEndBackgroundTask(_:)))
        ]
        for (original, counting) in pairs {
            guard let originalMethod = class_getInstanceMethod(UIApplication.self, original),
                  let countingMethod = class_getInstanceMethod(UIApplication.self, counting)
            else {
                XCTFail("UIApplication no longer has \(original)")
                continue
            }
            method_exchangeImplementations(originalMethod, countingMethod)
        }
    }
}

extension UIApplication {
    /// Swapped in for `beginBackgroundTask(withName:expirationHandler:)`; calling it calls the original.
    @objc dynamic func ledgerBeginBackgroundTask(
        withName name: String?,
        expirationHandler: (() -> Void)?
    ) -> UIBackgroundTaskIdentifier {
        let task = ledgerBeginBackgroundTask(withName: name, expirationHandler: expirationHandler)
        if name == BackgroundTaskLedger.name {
            MainActor.assumeIsolated { BackgroundTaskLedger.began(task) }
        }
        return task
    }

    /// Swapped in for `endBackgroundTask(_:)`; calling it calls the original.
    @objc dynamic func ledgerEndBackgroundTask(_ task: UIBackgroundTaskIdentifier) {
        MainActor.assumeIsolated { BackgroundTaskLedger.ended(task) }
        ledgerEndBackgroundTask(task)
    }
}

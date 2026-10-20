import PayabliSDKCore
import UIKit
import XCTest

final class UIKitAppLifecycleTests: XCTestCase {
    private let center = NotificationCenter()

    func testTheAppMerelyLosingFocusIsNotTheAppGoingAway() {
        XCTAssertEqual(UIKitAppLifecycle.backgroundNotification, UIApplication.didEnterBackgroundNotification)
    }

    func testBackgroundTimeIsAskedForBeforeTheNotificationsHandlerReturns() {
        let opened = CallCount()
        let lifecycle = UIKitAppLifecycle(center: center) {
            opened.increment()
            return BackgroundWindow {}
        }
        let backgroundings = lifecycle.backgroundings()

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        XCTAssertEqual(opened.value, 1, "asked for while the notification is still being delivered")
        _ = backgroundings
    }

    func testTheAppGoingAwayIsReported() async {
        let heard = expectation(description: "a backgrounding")
        let listening = listen(fulfilling: heard)

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        await fulfillment(of: [heard], timeout: 2)
        listening.cancel()
    }

    func testComingBackAndLeavingAgainIsReportedAgain() async {
        let heard = expectation(description: "two backgroundings")
        heard.expectedFulfillmentCount = 2
        let listening = listen(fulfilling: heard)

        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)
        center.post(name: UIApplication.willEnterForegroundNotification, object: nil)
        center.post(name: UIApplication.didEnterBackgroundNotification, object: nil)

        await fulfillment(of: [heard], timeout: 2)
        listening.cancel()
    }

    func testAWindowHandsItsTimeBackOnce() {
        let handedBack = CallCount()
        let window = BackgroundWindow { handedBack.increment() }

        window.close()
        window.close()

        XCTAssertEqual(handedBack.value, 1, "the work and the system's expiry can both close it")
    }

    /// Subscribes before returning, so a notification posted afterwards is in the stream.
    private func listen(fulfilling expectation: XCTestExpectation) -> Task<Void, Never> {
        let backgroundings = UIKitAppLifecycle(center: center) { BackgroundWindow {} }.backgroundings()
        return Task {
            for await window in backgroundings {
                window.close()
                expectation.fulfill()
            }
        }
    }
}

private final class CallCount: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    var value: Int {
        lock.withLock { count }
    }

    func increment() {
        lock.withLock { count += 1 }
    }
}

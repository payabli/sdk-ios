@testable import PayabliSDKCore
import XCTest

final class TelemetryQueueTests: XCTestCase {
    func testAFullQueueEvictsTheOldest() {
        var queue = TelemetryQueue(capacity: 2)
        _ = queue.offer(event("a"))
        _ = queue.offer(event("b"))
        let held = queue.offer(event("c"))

        XCTAssertEqual(held, 2)
        XCTAssertEqual(queue.drain(10).map(\.event), ["b", "c"])
    }

    func testEvictionsAreCountedOnceAndThenReset() {
        var queue = TelemetryQueue(capacity: 1)
        _ = queue.offer(event("a"))
        _ = queue.offer(event("b"))
        _ = queue.offer(event("c"))

        XCTAssertEqual(queue.takeDropCount(), 2)
        XCTAssertEqual(queue.takeDropCount(), 0)
    }

    func testARestoredCountIsAddedToOneTakenSince() {
        var queue = TelemetryQueue(capacity: 1)
        _ = queue.offer(event("a"))
        _ = queue.offer(event("b"))
        let taken = queue.takeDropCount()
        _ = queue.offer(event("c"))

        queue.restoreDropCount(taken)

        XCTAssertEqual(queue.takeDropCount(), 2)
    }

    func testADrainTakesTheOldestFirstAndNoMoreThanAsked() {
        var queue = TelemetryQueue(capacity: 10)
        ["a", "b", "c"].forEach { _ = queue.offer(event($0)) }

        XCTAssertEqual(queue.drain(2).map(\.event), ["a", "b"])
        XCTAssertEqual(queue.count, 1)
    }

    private func event(_ name: String) -> TelemetryEvent {
        TelemetryEvent(
            sdkVersion: "1.0.0",
            sessionId: "s",
            deviceIdHash: nil,
            entry: "e",
            environment: "sandbox",
            event: name,
            properties: [:],
            timestamp: Date()
        )
    }
}

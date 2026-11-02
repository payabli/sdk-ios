@testable import PayabliSDKCore
import XCTest

final class TelemetryQueueTests: XCTestCase {
    func testAFullQueueEvictsTheOldest() {
        var queue = TelemetryQueue(capacity: 2)
        _ = queue.offer(event("a"))
        _ = queue.offer(event("b"))
        _ = queue.offer(event("c"))

        XCTAssertEqual(queue.drain(10).map(\.event), ["b", "c"])
    }

    func testOffersAreCountedSinceTheLastDrainThatTookAnything() {
        var queue = TelemetryQueue(capacity: 10)
        XCTAssertEqual(queue.offer(event("a")), 1)
        XCTAssertEqual(queue.offer(event("b")), 2)
        _ = queue.drain(1)
        XCTAssertEqual(queue.offer(event("c")), 1)
        _ = queue.drain(10)
        XCTAssertEqual(queue.offer(event("d")), 1)
        _ = queue.drain(0)
        XCTAssertEqual(queue.offer(event("e")), 2, "a drain that took nothing is not a send attempt")
    }

    func testABatchPutBackIsNotCountedAsOffered() {
        var queue = TelemetryQueue(capacity: 10)
        _ = queue.offer(event("a"))
        _ = queue.offer(event("b"))
        let batch = queue.drain(10)
        queue.restoreFront(batch, droppedSinceLastSend: 0)

        XCTAssertEqual(queue.offer(event("c")), 1)
        XCTAssertEqual(queue.drain(10).map(\.event), ["a", "b", "c"])
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

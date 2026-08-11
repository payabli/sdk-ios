import PayabliSDKCore
import XCTest

final class EventMulticasterTests: XCTestCase {
    func testSingleSubscriberReceivesEvents() async {
        let multicaster = EventMulticaster<Int>()
        let stream = multicaster.stream()

        Task.detached {
            // Small delay to ensure the for-loop below is running before emitting.
            try? await Task.sleep(nanoseconds: 50_000_000)
            multicaster.emit(1)
            multicaster.emit(2)
            multicaster.finishAll()
        }

        var received: [Int] = []
        for await event in stream {
            received.append(event)
        }
        XCTAssertEqual(received, [1, 2])
    }

    func testMultipleSubscribersReceiveAllEvents() async {
        let multicaster = EventMulticaster<Int>()

        // Two independent streams.
        let stream1 = multicaster.stream()
        let stream2 = multicaster.stream()

        let collect1 = Task {
            var events: [Int] = []
            for await evt in stream1 {
                events.append(evt)
            }
            return events
        }
        let collect2 = Task {
            var events: [Int] = []
            for await evt in stream2 {
                events.append(evt)
            }
            return events
        }

        // Give them a moment to start iterating.
        try? await Task.sleep(nanoseconds: 50_000_000)
        multicaster.emit(10)
        multicaster.emit(20)
        multicaster.finishAll()

        let r1 = await collect1.value
        let r2 = await collect2.value
        XCTAssertEqual(r1, [10, 20])
        XCTAssertEqual(r2, [10, 20])
    }

    func testFinishAllTerminatesAllStreams() async {
        let multicaster = EventMulticaster<String>()
        let stream = multicaster.stream()

        let collectTask = Task {
            var events: [String] = []
            for await evt in stream {
                events.append(evt)
            }
            return events
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        multicaster.emit("hello")
        multicaster.finishAll()

        let result = await collectTask.value
        XCTAssertEqual(result, ["hello"])
    }

    func testWeakRemovalOnContinuationTermination() async {
        let multicaster = EventMulticaster<Int>()

        // Open a stream, then immediately cancel it to trigger onTermination.
        let stream = multicaster.stream()
        let task = Task {
            var first: Int?
            for await evt in stream {
                first = evt
                break // exit loop, causing continuation termination
            }
            return first
        }

        try? await Task.sleep(nanoseconds: 50_000_000)
        multicaster.emit(42)

        let result = await task.value
        XCTAssertEqual(result, 42)

        // After the stream terminates, emitting again should not crash.
        multicaster.emit(99)
        multicaster.finishAll()
    }
}

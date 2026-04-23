import XCTest
@testable import PayabliSDKPayIn

final class EventMulticasterTests: XCTestCase {

    func testSingleSubscriberReceivesEvents() async {
        let multicaster = EventMulticaster()
        let stream = multicaster.stream()

        Task.detached {
            // Small delay to ensure the for-loop below is running before emitting.
            try? await Task.sleep(nanoseconds: 50_000_000)
            multicaster.emit(.attestationStarted)
            multicaster.emit(.readerReady)
            multicaster.finishAll()
        }

        var received: [String] = []
        for await event in stream {
            switch event {
            case .attestationStarted: received.append("att")
            case .readerReady: received.append("rdy")
            default: break
            }
        }
        XCTAssertEqual(received, ["att", "rdy"])
    }

    func testMultipleSubscribersReceiveAllEvents() async {
        let multicaster = EventMulticaster()

        // Two independent streams.
        let stream1 = multicaster.stream()
        let stream2 = multicaster.stream()

        let collect1 = Task {
            var events: [String] = []
            for await evt in stream1 {
                if case .attestationStarted = evt { events.append("1-att") }
                if case .readerReady = evt { events.append("1-rdy") }
            }
            return events
        }
        let collect2 = Task {
            var events: [String] = []
            for await evt in stream2 {
                if case .attestationStarted = evt { events.append("2-att") }
                if case .readerReady = evt { events.append("2-rdy") }
            }
            return events
        }

        // Give them a moment to start iterating.
        try? await Task.sleep(nanoseconds: 50_000_000)
        multicaster.emit(.attestationStarted)
        multicaster.emit(.readerReady)
        multicaster.finishAll()

        let r1 = await collect1.value
        let r2 = await collect2.value
        XCTAssertEqual(r1, ["1-att", "1-rdy"])
        XCTAssertEqual(r2, ["2-att", "2-rdy"])
    }
}

import PayabliSDKCore
@testable import PayabliSDKTelemetry
import XCTest

final class TelemetryTransportTests: XCTestCase {
    // MARK: - Sentry bridge

    final class CapturingSentryBridge: PayabliSentryBridge, @unchecked Sendable {
        var breadcrumbs: [(String, [String: Any])] = []
        var errors: [(String, [String: String], [String: Any])] = []
        func addBreadcrumb(_ category: String, data: [String: Any]) {
            breadcrumbs.append((category, data))
        }

        func captureError(_ message: String, tags: [String: String], extra: [String: Any]) {
            errors.append((message, tags, extra))
        }
    }

    func testSentryTransportRoutesFailuresToCapture() async {
        let bridge = CapturingSentryBridge()
        let transport = SentryTelemetryTransport(bridge: bridge)
        await transport.send([
            TelemetryEvent(
                sdkVersion: "1",
                sessionId: "s",
                deviceIdHash: nil,
                entry: "e",
                environment: "sandbox",
                event: "ttp.charge.failed",
                properties: ["errorCode": "X"]
            ),
            TelemetryEvent(
                sdkVersion: "1",
                sessionId: "s",
                deviceIdHash: nil,
                entry: "e",
                environment: "sandbox",
                event: "ttp.charge.started",
                properties: ["amount": "10"]
            )
        ])
        XCTAssertEqual(bridge.errors.count, 1)
        XCTAssertEqual(bridge.errors.first?.0, "ttp.charge.failed")
        XCTAssertEqual(bridge.breadcrumbs.count, 1)
        XCTAssertEqual(bridge.breadcrumbs.first?.0, "ttp.charge.started")
    }

    // MARK: - PostHog bridge

    final class CapturingPostHogBridge: PayabliPostHogBridge, @unchecked Sendable {
        var captured: [(String, String, [String: Any])] = []
        var flushCount = 0
        func capture(_ event: String, distinctId: String, properties: [String: Any]) {
            captured.append((event, distinctId, properties))
        }

        func flush() {
            flushCount += 1
        }
    }

    func testPostHogTransportCapturesWithHashedEntryAsDistinctId() async {
        let bridge = CapturingPostHogBridge()
        let transport = PostHogTelemetryTransport(bridge: bridge)
        await transport.send([
            TelemetryEvent(
                sdkVersion: "1",
                sessionId: "s",
                deviceIdHash: nil,
                entry: "partner_entry",
                environment: "sandbox",
                event: "tokenization.started",
                properties: ["method": "card"]
            )
        ])
        XCTAssertEqual(bridge.captured.count, 1)
        let (name, distinctId, props) = bridge.captured.first!
        XCTAssertEqual(name, "tokenization.started")
        XCTAssertEqual(distinctId, "partner_entry")
        XCTAssertEqual(props["method"] as? String, "card")
        XCTAssertEqual(props["sdk_version"] as? String, "1")
        XCTAssertEqual(bridge.flushCount, 1)
    }
}

import Foundation
@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// A card-present route call is logged by its route template, never by the resolved path, and none of the
/// attestation material, device identity, activation code or entry point it sends or receives reaches a log line.
/// Each case anchors on the record it expects before asserting every sentinel is absent.
final class DeviceRouteLoggingTests: XCTestCase {
    private static let sentinels = [
        "SENTINEL-KEYID",
        "SENTINEL-ATTESTATION",
        "SENTINEL-DEVICEID",
        "SENTINEL-CHALLENGEID",
        "SENTINEL-ASSERTION",
        "SENTINEL-ACTIVATIONCODE",
        "SENTINEL-ENTRY",
        "SENTINEL-TRANSID"
    ]

    private static let postRoutes: [DeviceRoute] = [.challenge, .register, .attest, .activate]

    func testEachPostIsLoggedByItsTemplateOnSuccess() async throws {
        for route in Self.postRoutes {
            let sink = LogLineSink()
            let transport = RecordingRouteTransport(answer: .status(200, body: Self.echo))

            _ = try await post(route, over: transport, sink: sink)

            XCTAssertEqual(transport.sent.map(\.path), [route.template], "a POST route embeds no identifier")
            XCTAssertEqual(transport.sent.map(\.route), [route.template])
            assertLineLogged("[\(route.rawValue)] → POST /api/v2/device/taptopay/\(route.rawValue) bytes=", in: sink)
            assertLineLogged("[\(route.rawValue)] ← [200]", in: sink)
            assertNoneLogged(Self.sentinels, in: sink)
        }
    }

    func testEachPostDeclineQuotingASentinelLogsItsCodeOnly() async throws {
        for route in Self.postRoutes {
            let sink = LogLineSink()

            do {
                _ = try await post(route, over: RecordingRouteTransport(answer: .status(200, body: Self.decline)), sink: sink)
                XCTFail("[\(route.rawValue)] a decline returned an answer")
            } catch {}

            assertLineLogged("[\(route.rawValue)] → POST /api/v2/device/taptopay/\(route.rawValue)", in: sink)
            assertLineLogged("[\(route.rawValue)] declined (code=409)", in: sink)
            assertNoneLogged(Self.sentinels, in: sink)
        }
    }

    func testEachPostTransportErrorLogsItsKindOnly() async throws {
        for route in Self.postRoutes {
            let sink = LogLineSink()

            do {
                _ = try await post(route, over: RecordingRouteTransport(answer: .error(SentinelError())), sink: sink)
                XCTFail("[\(route.rawValue)] a failed send returned an answer")
            } catch {}

            assertLineLogged("[\(route.rawValue)] → POST /api/v2/device/taptopay/\(route.rawValue)", in: sink)
            assertLineLogged("[\(route.rawValue)] transport error:", in: sink)
            assertNoneLogged(Self.sentinels, in: sink)
        }
    }

    func testConfigIsLoggedByItsTemplateAndNeverByTheEntryPointInItsPath() async throws {
        let answers: [RecordingRouteTransport.Answer] = [.status(200, body: Self.echo), .status(200, body: Self.decline)]
        for answer in answers {
            let sink = LogLineSink()
            let client = DeviceServiceClient(transport: RecordingRouteTransport(answer: answer), logger: sink.logger)

            _ = try await client.get(.config, Self.configRequest)

            assertLineLogged("[config] → GET /api/v2/device/taptopay/config/{entry}", in: sink)
            assertLineLogged("[config] ← [200]", in: sink)
            assertNoneLogged(Self.sentinels, in: sink)
        }
    }

    func testAConfigTransportErrorLogsNoPath() async throws {
        let sink = LogLineSink()
        let client = DeviceServiceClient(transport: RecordingRouteTransport(answer: .error(SentinelError())), logger: sink.logger)

        do {
            _ = try await client.get(.config, Self.configRequest)
            XCTFail("a failed send returned an answer")
        } catch {}

        assertLineLogged("[config] → GET /api/v2/device/taptopay/config/{entry}", in: sink)
        assertNoneLogged(Self.sentinels, in: sink)
    }

    func testACloseIsLoggedByItsTemplateAndNeverByTheTransactionInItsPath() async throws {
        let sink = LogLineSink()
        let transport = RecordingRouteTransport(answer: .status(200, body: Self.echo))
        let client = TTPTransactionClient(
            transport: transport,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            logger: sink.logger
        )

        try await client.close(paymentTransId: "SENTINEL-TRANSID")

        XCTAssertEqual(transport.sent.map(\.path), ["/api/v2/MoneyIn/update/SENTINEL-TRANSID"])
        XCTAssertEqual(transport.sent.map(\.route), ["/api/v2/MoneyIn/update/{transId}"])
        assertLineLogged("[update/1] → PATCH /api/v2/MoneyIn/update/{transId} bytes=", in: sink)
        assertNoneLogged(Self.sentinels, in: sink)
    }

    // MARK: - Fixtures

    private static let assertion = AssertionHeaders(
        assertion: "SENTINEL-ASSERTION",
        keyId: "SENTINEL-KEYID",
        deviceId: "SENTINEL-DEVICEID",
        timestamp: "1700000000"
    )

    /// Every field a device route sends, each carrying a sentinel.
    private static let body = [
        "keyId": "SENTINEL-KEYID",
        "attestation": "SENTINEL-ATTESTATION",
        "deviceId": "SENTINEL-DEVICEID",
        "challengeId": "SENTINEL-CHALLENGEID",
        "activationCode": "SENTINEL-ACTIVATIONCODE",
        "entry": "SENTINEL-ENTRY"
    ]

    /// A success whose payload repeats what was sent.
    private static let echo = Data(#"""
    {"isSuccess":true,"responseCode":1,"responseData":{"challengeId":"SENTINEL-CHALLENGEID",\#
    "keyId":"SENTINEL-KEYID","deviceId":"SENTINEL-DEVICEID","entry":"SENTINEL-ENTRY"}}
    """#.utf8)

    /// A decline whose `resultText` quotes what was sent.
    private static let decline = Data(#"""
    {"isSuccess":false,"responseData":{"resultCode":409,\#
    "resultText":"device SENTINEL-DEVICEID key SENTINEL-KEYID code SENTINEL-ACTIVATIONCODE"}}
    """#.utf8)

    private static let configRequest = PayabliRequest(
        method: .get,
        path: PercentEncoding.path(from: DeviceRoute.config.template, segment: PercentEncoding.segment("SENTINEL-ENTRY")),
        route: DeviceRoute.config.template,
        headers: assertion.asDictionary
    )

    private func post(_ route: DeviceRoute, over transport: RecordingRouteTransport, sink: LogLineSink) async throws -> PayabliResponse {
        try await DeviceServiceClient(transport: transport, logger: sink.logger).post(
            route,
            body: Self.body,
            assertion: Self.assertion,
            makeDeclineError: { _, _ in nil }
        )
    }
}

/// An error whose every description quotes a sentinel, so a log line that prints one is caught.
private struct SentinelError: Error, CustomStringConvertible, LocalizedError {
    var description: String {
        "SENTINEL-DEVICEID SENTINEL-KEYID"
    }

    var errorDescription: String? {
        description
    }
}

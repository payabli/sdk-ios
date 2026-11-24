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
            let sink = RecordingLogSink()
            let transport = FixedTransport(answer: .status(200, body: Self.echo))

            _ = try await post(route, over: transport, sink: sink)

            XCTAssertEqual(transport.sent.map(\.path), [route.template], "a POST route embeds no identifier")
            XCTAssertEqual(transport.sent.map(\.route), [route.template])
            assertLogged("[\(route.rawValue)] → POST /api/v2/device/taptopay/\(route.rawValue) bytes=", in: sink)
            assertLogged("[\(route.rawValue)] ← [200]", in: sink)
            assertNeverLogged(Self.sentinels, in: [sink])
        }
    }

    func testEachPostDeclineQuotingASentinelLogsItsCodeOnly() async throws {
        for route in Self.postRoutes {
            let sink = RecordingLogSink()

            do {
                _ = try await post(route, over: FixedTransport(answer: .status(200, body: Self.decline)), sink: sink)
                XCTFail("[\(route.rawValue)] a decline returned an answer")
            } catch {}

            assertLogged("[\(route.rawValue)] → POST /api/v2/device/taptopay/\(route.rawValue)", in: sink)
            assertLogged("[\(route.rawValue)] declined (code=409)", in: sink)
            assertNeverLogged(Self.sentinels, in: [sink])
        }
    }

    func testEachPostTransportErrorLogsItsKindOnly() async throws {
        for route in Self.postRoutes {
            let sink = RecordingLogSink()

            do {
                _ = try await post(route, over: FixedTransport(answer: .error(SentinelError())), sink: sink)
                XCTFail("[\(route.rawValue)] a failed send returned an answer")
            } catch {}

            assertLogged("[\(route.rawValue)] → POST /api/v2/device/taptopay/\(route.rawValue)", in: sink)
            assertLogged("[\(route.rawValue)] transport error:", in: sink)
            assertNeverLogged(Self.sentinels, in: [sink])
        }
    }

    func testConfigIsLoggedByItsTemplateAndNeverByTheEntryPointInItsPath() async throws {
        let answers: [FixedTransport.Answer] = [.status(200, body: Self.echo), .status(200, body: Self.decline)]
        for answer in answers {
            let sink = RecordingLogSink()
            let client = DeviceServiceClient(transport: FixedTransport(answer: answer), logger: Self.logger(sink))

            _ = try await client.get(.config, Self.configRequest)

            assertLogged("[config] → GET /api/v2/device/taptopay/config/{entry}", in: sink)
            assertLogged("[config] ← [200]", in: sink)
            assertNeverLogged(Self.sentinels, in: [sink])
        }
    }

    func testAConfigTransportErrorLogsNoPath() async throws {
        let sink = RecordingLogSink()
        let client = DeviceServiceClient(transport: FixedTransport(answer: .error(SentinelError())), logger: Self.logger(sink))

        do {
            _ = try await client.get(.config, Self.configRequest)
            XCTFail("a failed send returned an answer")
        } catch {}

        assertLogged("[config] → GET /api/v2/device/taptopay/config/{entry}", in: sink)
        assertNeverLogged(Self.sentinels, in: [sink])
    }

    func testACloseIsLoggedByItsTemplateAndNeverByTheTransactionInItsPath() async throws {
        let sink = RecordingLogSink()
        let transport = FixedTransport(answer: .status(200, body: Self.echo))
        let client = TTPTransactionClient(
            transport: transport,
            retryPolicy: RetryPolicy(maxAttempts: 1, baseDelay: 0, maxDelay: 0, multiplier: 1, maxJitter: 0),
            logger: Self.logger(sink)
        )

        try await client.close(paymentTransId: "SENTINEL-TRANSID")

        XCTAssertEqual(transport.sent.map(\.path), ["/api/v2/MoneyIn/update/SENTINEL-TRANSID"])
        XCTAssertEqual(transport.sent.map(\.route), ["/api/v2/MoneyIn/update/{transId}"])
        assertLogged("[update/1] → PATCH /api/v2/MoneyIn/update/{transId} bytes=", in: sink)
        assertNeverLogged(Self.sentinels, in: [sink])
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

    private static func logger(_ sink: RecordingLogSink) -> PayabliLogger {
        PayabliLogger(category: .taptopay, sink: sink)
    }

    private func post(_ route: DeviceRoute, over transport: FixedTransport, sink: RecordingLogSink) async throws -> PayabliResponse {
        try await DeviceServiceClient(transport: transport, logger: Self.logger(sink)).post(
            route,
            body: Self.body,
            assertion: Self.assertion,
            makeDeclineError: { _, _ in nil }
        )
    }

    private func assertLogged(_ needle: String, in sink: RecordingLogSink, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(
            sink.lines.contains { $0.contains(needle) },
            "no record matching \"\(needle)\" — wrote: \(sink.lines)",
            file: file,
            line: line
        )
    }

    private func assertNeverLogged(
        _ sentinels: [String],
        in sinks: [RecordingLogSink],
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let lines = sinks.flatMap(\.lines)
        XCTAssertFalse(lines.isEmpty, "nothing was logged, so absence proves nothing", file: file, line: line)
        for sentinel in sentinels {
            XCTAssertFalse(lines.contains { $0.contains(sentinel) }, "\"\(sentinel)\" reached the log: \(lines)", file: file, line: line)
        }
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

/// Records every line written, so a test can assert what a log never carries.
private final class RecordingLogSink: LogSink, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [String] = []

    var lines: [String] {
        lock.withLock { recorded }
    }

    func write(level _: PayabliLogger.Level, category _: PayabliLogger.Category, message: String) {
        lock.withLock { recorded.append(message) }
    }
}

/// Answers every request the same way, and keeps what it was sent.
private final class FixedTransport: PayabliTransport, @unchecked Sendable {
    enum Answer: Sendable {
        case status(Int, body: Data)
        case error(any Error)
    }

    private let answer: Answer
    private let lock = NSLock()
    private var requests: [PayabliRequest] = []

    init(answer: Answer) {
        self.answer = answer
    }

    var sent: [PayabliRequest] {
        lock.withLock { requests }
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        lock.withLock { requests.append(request) }
        switch answer {
        case let .status(code, body): return PayabliResponse(statusCode: code, headers: [:], body: body)
        case let .error(error): throw error
        }
    }

    func performV2<T: Decodable & Sendable>(_: PayabliRequest, decoding _: T.Type) async throws -> PayabliV2Envelope<T> {
        throw URLError(.unsupportedURL)
    }
}

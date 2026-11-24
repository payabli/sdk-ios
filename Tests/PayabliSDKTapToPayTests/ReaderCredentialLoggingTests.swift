import Foundation
@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import PayabliSDKTestUtils
import XCTest

/// The card reader's processor credentials arrive in the configuration answer and go to the reader. Neither the
/// configuration call nor the reader's intake of them writes a credential value to a log line, whatever the answer.
/// Each case anchors on the record it expects before asserting every credential is absent.
@available(iOS 16.7, *)
final class ReaderCredentialLoggingTests: XCTestCase {
    private static let secrets = ["SENTINEL-SECRETKEY", "SENTINEL-APIKEY"]
    private static let entry = "entry-1"

    func testAConfigurationThatCarriesTheCredentialsLogsNoneOfThem() async throws {
        let sink = LogLineSink()
        let transport = RecordingRouteTransport(answer: .status(200, body: Self.configuration))

        let config = try await fetchConfig(over: transport, sink: sink, entry: "entry/1")

        XCTAssertEqual(config.providerCredentials["secretKey"], "SENTINEL-SECRETKEY", "the credentials reached the caller")
        XCTAssertEqual(transport.sent.map(\.path), ["/api/v2/device/taptopay/config/entry%2F1"])
        XCTAssertEqual(transport.sent.map(\.route), ["/api/v2/device/taptopay/config/{entry}"])
        assertLineLogged("[config] → GET /api/v2/device/taptopay/config/{entry}", in: sink)
        assertLineLogged("[config] ← [200]", in: sink)
        assertNoneLogged(Self.secrets, in: sink)
    }

    func testADeclineQuotingTheCredentialsLogsItsCodeOnly() async throws {
        let sink = LogLineSink()

        do {
            _ = try await fetchConfig(answering: .status(200, body: Self.decline), sink: sink)
            XCTFail("a decline returned a configuration")
        } catch {}

        assertLineLogged("[config] declined (isSuccess=false code=409)", in: sink)
        assertNoneLogged(Self.secrets, in: sink)
    }

    func testAConfigurationThatCannotBeReadLogsNoneOfItsBody() async throws {
        let sink = LogLineSink()

        do {
            _ = try await fetchConfig(answering: .status(200, body: Self.unreadable), sink: sink)
            XCTFail("an unreadable configuration was returned")
        } catch {}

        assertLineLogged("[config] payload decode failed", in: sink)
        assertNoneLogged(Self.secrets, in: sink)
    }

    func testAServerFailureCarryingTheCredentialsLogsItsStatusOnly() async throws {
        let sink = LogLineSink()

        do {
            _ = try await fetchConfig(answering: .status(500, body: Self.configuration), sink: sink)
            XCTFail("a server failure returned a configuration")
        } catch {}

        assertLineLogged("[config] ← [500]", in: sink)
        assertNoneLogged(Self.secrets, in: sink)
    }

    func testTheReaderTakesTheCredentialsWithoutLoggingThem() throws {
        let sink = LogLineSink()

        try FiservCardReader(logger: sink.logger).configure(credentials: Self.credentials)

        assertLineLogged("[fiserv.configure] optional credentials missing, using defaults:", in: sink)
        assertNoneLogged(Self.secrets, in: sink)
    }

    func testEachCredentialRefusalNamesTheProblemAndNoValue() throws {
        let refusals: [(credentials: [String: String], line: String)] = [
            (Self.credentials.merging(["merchantId": " "]) { $1 }, "required credentials blank: merchantId"),
            (Self.credentials.merging(["environment": "SENTINEL-SECRETKEY"]) { $1 }, "environment is not one the reader knows"),
            (Self.credentials.merging(["currencyCode": "SENTINEL-APIKEY"]) { $1 }, "currencyCode is not one the reader is armed in")
        ]
        for refusal in refusals {
            let sink = LogLineSink()

            XCTAssertThrowsError(try FiservCardReader(logger: sink.logger).configure(credentials: refusal.credentials))

            assertLineLogged("[fiserv.configure] \(refusal.line)", in: sink)
            assertNoneLogged(Self.secrets, in: sink)
        }
    }

    // MARK: - Fixtures

    private static let credentials = [
        "secretKey": "SENTINEL-SECRETKEY",
        "apiKey": "SENTINEL-APIKEY",
        "merchantId": "m",
        "terminalId": "t",
        "environment": "sandbox",
        "currencyCode": "USD"
    ]

    private static let configuration = Data(#"""
    {"isSuccess":true,"responseCode":1,"responseData":{"credentials":{"secretKey":"SENTINEL-SECRETKEY",\#
    "apiKey":"SENTINEL-APIKEY","merchantId":"m","terminalId":"t","environment":"sandbox","currencyCode":"USD"}}}
    """#.utf8)

    /// A decline whose `resultText` quotes the credentials.
    private static let decline = Data(#"""
    {"isSuccess":false,"responseData":{"resultCode":409,\#
    "resultText":"secretKey SENTINEL-SECRETKEY apiKey SENTINEL-APIKEY"}}
    """#.utf8)

    /// A success whose credentials are not the string map the route answers with.
    private static let unreadable = Data(#"""
    {"isSuccess":true,"responseCode":1,"responseData":{"credentials":["SENTINEL-SECRETKEY","SENTINEL-APIKEY"]}}
    """#.utf8)

    private func fetchConfig(answering answer: RecordingRouteTransport.Answer, sink: LogLineSink) async throws -> TTPConfig {
        try await fetchConfig(over: RecordingRouteTransport(answer: answer), sink: sink, entry: Self.entry)
    }

    private func fetchConfig(over transport: RecordingRouteTransport, sink: LogLineSink, entry: String) async throws -> TTPConfig {
        let attestation = MockDeviceAttestationService()
        attestation.bindings = [entry: "device-1"]
        return try await TTPConfigClient(transport: transport, attestation: attestation, logger: sink.logger)
            .fetchConfig(entry: entry)
    }
}

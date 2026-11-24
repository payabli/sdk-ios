@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// The transport names a request in its log by the route's template, never by the resolved path, which can carry an
/// identifier. Each case anchors on the record it expects before asserting the identifier is absent.
final class RequestRouteLoggingTests: XCTestCase {
    /// Its last four characters appear in no anchor, so the tail sweep cannot match a template.
    private static let identifier = "SENTINEL-TRANSID-7Q9Z"
    private static let template = "/api/v2/MoneyIn/update/{transId}"

    func testASendAndItsAnswerAreLoggedByTheTemplateAndNeverByThePath() async throws {
        let stub = RecordingStub(status: 200)
        stub.install()
        defer { stub.uninstall() }
        let sink = RecordingLogSink()

        _ = try await makeTransport(sink: sink).perform(Self.request(route: Self.template))

        XCTAssertEqual(stub.count, 1, "the request reached the network, so there was a path to leak")
        assertLogged("→ PATCH \(Self.template)", in: sink, category: .network)
        assertLogged("← PATCH \(Self.template) [200]", in: sink, category: .network)
        assertNeverLogged([Self.identifier], in: [sink])
    }

    func testANetworkFailureIsLoggedByTheTemplateAndNeverByThePath() async throws {
        StubURLProtocol.handler = { _ in throw URLError(.notConnectedToInternet) }
        defer { StubURLProtocol.handler = nil }
        let sink = RecordingLogSink()

        do {
            _ = try await makeTransport(sink: sink).perform(Self.request(route: Self.template))
            XCTFail("a request the network refused returned an answer")
        } catch let error as PayabliGenericError {
            XCTAssertEqual(error.type, .networkError)
        }

        assertLogged("Network error on \(Self.template)", in: sink, category: .network)
        assertNeverLogged([Self.identifier], in: [sink])
    }

    func testARequestWithoutATemplateIsLoggedRedacted() async throws {
        let stub = RecordingStub(status: 200)
        stub.install()
        defer { stub.uninstall() }
        let sink = RecordingLogSink()

        _ = try await makeTransport(sink: sink).perform(Self.request(route: nil))

        assertLogged("→ PATCH [REDACTED]", in: sink, category: .network)
        assertNeverLogged([Self.identifier], in: [sink])
    }

    // MARK: - Helpers

    private static func request(route: String?) -> PayabliRequest {
        PayabliRequest(
            method: .patch,
            path: PercentEncoding.path(from: template, segment: PercentEncoding.segment(identifier)),
            route: route
        )
    }

    private func makeTransport(sink: RecordingLogSink) throws -> any PayabliTransport {
        try makeAuthenticatedStack(auth: makeTestAuth(), sink: sink)
    }
}

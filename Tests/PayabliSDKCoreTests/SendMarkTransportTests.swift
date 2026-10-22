@testable import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

/// Every 401 lowers the payment's send mark, since the service ran nothing for that send, and an answer the
/// service acted on leaves it raised.
final class SendMarkTransportTests: XCTestCase {
    private static let unauthorized = 401

    func testAReplayRefusedWithA401AgainLowersTheMark() async throws {
        let stub = RecordingStub(status: Self.unauthorized)
        stub.install()
        defer { stub.uninstall() }

        let transport = try makeAuthenticatedStack(auth: makeTestAuth(tokenProvider: { "refreshed-token" }))
        let mark = PayabliSendMark()

        let refused = await sendUnderMark(mark, ping(), on: transport)

        XCTAssertNotNil(refused, "a replay refused in turn ends the request")
        XCTAssertEqual(stub.count, 2, "the request and its replay both reached the network")
        XCTAssertFalse(mark.mayHaveLeft, "both sends were refused with 401, so neither ran")
    }

    func testAReplayAnsweredOtherwiseRaisesTheMark() async throws {
        let stub = RecordingStub { request in
            let refreshed = request.value(forHTTPHeaderField: "Authorization")?.contains("refreshed-token") == true
            return (refreshed ? 500 : Self.unauthorized, Data())
        }
        stub.install()
        defer { stub.uninstall() }

        let transport = try makeAuthenticatedStack(auth: makeTestAuth(tokenProvider: { "refreshed-token" }))
        let mark = PayabliSendMark()

        _ = await sendUnderMark(mark, ping(), on: transport)

        XCTAssertEqual(stub.count, 2)
        XCTAssertTrue(mark.mayHaveLeft, "the replay was answered with something other than 401")
    }

    func testA401TheRequestNamesAsARefusalOfTheCallerLowersTheMark() async throws {
        let stub = RecordingStub(status: Self.unauthorized)
        stub.install()
        defer { stub.uninstall() }

        let transport = try makeAuthenticatedStack(auth: makeTestAuth())
        let mark = PayabliSendMark()

        _ = await sendUnderMark(
            mark,
            PayabliRequest(method: .get, path: "/api/v2/ping", isCallerRefusal: { $0.statusCode == Self.unauthorized }),
            on: transport
        )

        XCTAssertEqual(stub.count, 1, "a refusal of the caller is neither refreshed nor replayed")
        XCTAssertFalse(mark.mayHaveLeft, "a send refused with 401 ran nothing")
    }

    private func ping() -> PayabliRequest {
        PayabliRequest(method: .get, path: "/api/v2/ping")
    }

    /// Sends `request` under `mark`, returning what it threw, or nil when it returned an answer.
    private func sendUnderMark(
        _ mark: PayabliSendMark,
        _ request: PayabliRequest,
        on transport: any PayabliTransport
    ) async -> (any Error)? {
        do {
            _ = try await PayabliSendMark.$current.withValue(mark) { try await transport.perform(request) }
            return nil
        } catch {
            return error
        }
    }
}

import XCTest
@testable import PayabliSDKCore

final class AuthenticatedTransportTests: XCTestCase {

    func testInjectsBearerHeaderOnEveryRequest() async throws {
        let mock = MockTransport(scripted: [
            .response(statusCode: 200, body: Data("{}".utf8))
        ])
        let auth = PayabliAuth(config: PayabliConfig(
            accessToken: "tok-1",
            entryPoint: "demo",
            environment: .sandbox
        ))
        let decorator = AuthenticatedTransport(base: mock, auth: auth)
        let request = PayabliRequest(method: .get, path: "/x")
        _ = try await decorator.perform(request)

        let captured = await mock.captured()
        XCTAssertEqual(captured.first?.headers["Authorization"], "Bearer tok-1")
    }

    func testRefreshesAndRetriesOn401() async throws {
        let mock = MockTransport(scripted: [
            .response(statusCode: 401, body: Data()),
            .response(statusCode: 200, body: Data("{}".utf8))
        ])
        let auth = PayabliAuth(config: PayabliConfig(
            accessToken: "old",
            tokenProvider: { "new" },
            entryPoint: "demo",
            environment: .sandbox
        ))
        let decorator = AuthenticatedTransport(base: mock, auth: auth)
        let request = PayabliRequest(method: .get, path: "/x")
        let response = try await decorator.perform(request)

        XCTAssertEqual(response.statusCode, 200)
        let captured = await mock.captured()
        XCTAssertEqual(captured.count, 2)
        XCTAssertEqual(captured[0].headers["Authorization"], "Bearer old")
        XCTAssertEqual(captured[1].headers["Authorization"], "Bearer new")
    }

    func testPerformV2MapsNon2xxToTypedError() async {
        let mock = MockTransport(scripted: [
            .response(statusCode: 500, body: Data("{}".utf8))
        ])
        let auth = PayabliAuth(config: PayabliConfig(
            accessToken: "tok",
            entryPoint: "demo",
            environment: .sandbox
        ))
        let decorator = AuthenticatedTransport(base: mock, auth: auth)
        let request = PayabliRequest(method: .get, path: "/x")

        do {
            let _: PayabliV2Envelope<DummyPayload> = try await decorator.performV2(request, decoding: DummyPayload.self)
            XCTFail("expected throw")
        } catch is PayabliPaymentError {
            // HTTP 500 with decodable body → .server; mapPayabliHTTPError ran correctly
        } catch is PayabliGenericError {
            // Fallback: .unknown if body didn't decode to PayabliServerError; mapping still ran
        } catch {
            XCTFail("wrong error: \(type(of: error)) - \(error)")
        }
    }

    func testThrowsTokenExpiredAfterDouble401() async {
        let mock = MockTransport(scripted: [
            .response(statusCode: 401, body: Data()),
            .response(statusCode: 401, body: Data())
        ])
        let auth = PayabliAuth(config: PayabliConfig(
            accessToken: "old",
            tokenProvider: { "new" },
            entryPoint: "demo",
            environment: .sandbox
        ))
        let decorator = AuthenticatedTransport(base: mock, auth: auth)
        let request = PayabliRequest(method: .get, path: "/x")
        do {
            _ = try await decorator.perform(request)
            XCTFail("expected throw")
        } catch let error as PayabliGenericError {
            XCTAssertEqual(error.code, .tokenExpired)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}

private struct DummyPayload: Decodable, Sendable {}

actor MockTransport: PayabliTransport {
    enum Scripted: Sendable {
        case response(statusCode: Int, body: Data)
    }

    private var scripted: [Scripted]
    private var requests: [PayabliRequest] = []

    init(scripted: [Scripted]) {
        self.scripted = scripted
    }

    func captured() -> [PayabliRequest] { requests }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        requests.append(request)
        guard !scripted.isEmpty else {
            throw PayabliGenericError(code: .networkError, reason: "no more scripted responses")
        }
        let next = scripted.removeFirst()
        switch next {
        case let .response(statusCode, body):
            return PayabliResponse(statusCode: statusCode, headers: [:], body: body)
        }
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        let response = try await perform(request)
        return try JSONDecoder().decode(PayabliV2Envelope<T>.self, from: response.body)
    }
}

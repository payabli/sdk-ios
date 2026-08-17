import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

final class PayabliSessionTests: XCTestCase {
    func testSessionExposesAuthAndService() async {
        let config = PayabliConfig(
            accessToken: "abc",
            entryPoint: "demo",
            environment: .sandbox
        )
        let session = PayabliSession(config: config)
        let token = await session.auth.currentAccessToken()
        XCTAssertEqual(token, "abc")
        XCTAssertEqual(session.config.entryPoint, "demo")
    }

    func testSessionAcceptsCustomURLSession() async throws {
        let expectedBody = Data("{\"hello\":\"world\"}".utf8)
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v2/test-wiring")
            return (
                HTTPURLResponse(
                    url: request.url!,
                    statusCode: 200,
                    httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Type": "application/json"]
                )!,
                expectedBody
            )
        }
        defer { StubURLProtocol.handler = nil }

        let urlSession = StubURLProtocol.makeSession()
        let config = PayabliConfig(
            accessToken: "tok",
            entryPoint: "demo",
            environment: .sandbox
        )
        let session = PayabliSession(config: config, urlSession: urlSession)

        let request = PayabliRequest(method: .get, path: "/api/v2/test-wiring")
        let response = try await session.service.perform(request)

        XCTAssertEqual(response.statusCode, 200)
        XCTAssertEqual(response.body, expectedBody)
    }
}

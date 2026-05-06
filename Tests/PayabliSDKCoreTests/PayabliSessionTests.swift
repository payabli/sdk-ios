import XCTest
import PayabliSDKCore
import PayabliSDKTestUtils

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

    func testSessionAcceptsCustomURLSession() {
        let stubConfig = URLSessionConfiguration.ephemeral
        stubConfig.protocolClasses = [StubURLProtocol.self]
        let urlSession = URLSession(configuration: stubConfig)
        let config = PayabliConfig(
            accessToken: "abc",
            entryPoint: "demo",
            environment: .sandbox
        )
        let session = PayabliSession(config: config, urlSession: urlSession)
        XCTAssertNotNil(session.service)
    }
}

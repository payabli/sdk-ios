import XCTest
@testable import PayabliSDKCore

final class PayabliEnvironmentTests: XCTestCase {
    func testBaseURLsMatchPRD() {
        #if DEBUG
        XCTAssertEqual(PayabliEnvironment.local.baseURL.absoluteString, "https://wallets-test.ngrok.app")
        #endif
        XCTAssertEqual(PayabliEnvironment.qa.baseURL.absoluteString, "https://api-qa.payabli.com")
        XCTAssertEqual(PayabliEnvironment.sandbox.baseURL.absoluteString, "https://api-sandbox.payabli.com")
        XCTAssertEqual(PayabliEnvironment.production.baseURL.absoluteString, "https://api.payabli.com")
    }
}

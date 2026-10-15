import XCTest

/// The three forms the override documents, and the values that name no host.
final class TokenHostOverrideTests: XCTestCase {
    private func url(_ raw: String) -> String? {
        TokenHostOverride.baseURL(from: raw, defaultPort: 8787)?.absoluteString
    }

    // MARK: - Documented forms

    func testBareHostTakesTheDefaultPort() {
        XCTAssertEqual(url("mac.local"), "http://mac.local:8787")
    }

    func testHostAndPortKeepsThePort() {
        XCTAssertEqual(url("mac.local:8788"), "http://mac.local:8788")
        XCTAssertEqual(url("192.168.1.20:8791"), "http://192.168.1.20:8791")
    }

    func testFullURLIsTakenAsWritten() {
        XCTAssertEqual(url("http://mac.local:8788"), "http://mac.local:8788")
    }

    // MARK: - No host

    func testAPortThatIsNotANumberNamesNoHost() {
        XCTAssertNil(url("mac.local:88a"))
    }

    func testAPortWithNoHostNamesNoHost() {
        XCTAssertNil(url(":8788"))
    }

    func testAURLWithNoHostNamesNoHost() {
        XCTAssertNil(url("http://"))
    }
}

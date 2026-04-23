import XCTest
@testable import PayabliSDKPayIn

final class PayabliSDKPayInTests: XCTestCase {
    func testVersionIsPopulated() {
        XCTAssertFalse(PayabliSDKPayIn.version.isEmpty)
    }
}

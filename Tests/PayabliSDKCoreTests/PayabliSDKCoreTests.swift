import XCTest
@testable import PayabliSDKCore

final class PayabliSDKCoreTests: XCTestCase {
    func testVersionIsPopulated() {
        XCTAssertFalse(PayabliSDKCore.version.isEmpty)
    }
}

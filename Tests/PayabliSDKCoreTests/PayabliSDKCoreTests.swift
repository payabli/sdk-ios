import XCTest
import PayabliSDKCore

final class PayabliSDKCoreTests: XCTestCase {
    func testVersionIsPopulated() {
        XCTAssertFalse(PayabliCore.version.isEmpty)
    }
}

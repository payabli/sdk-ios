import PayabliSDKCore
import XCTest

final class PayabliSDKCoreTests: XCTestCase {
    func testVersionIsPopulated() {
        XCTAssertFalse(PayabliCore.version.isEmpty)
    }
}

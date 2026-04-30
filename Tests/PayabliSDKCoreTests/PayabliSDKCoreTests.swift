import XCTest
@testable import PayabliSDKCore

final class PayabliSDKCoreTests: XCTestCase {
    func testVersionIsPopulated() {
        XCTAssertFalse(PayabliCore.version.isEmpty)
    }
}

import PayabliSDKCore
import PayabliSDKTapToPay
import XCTest

final class ModuleVersionTests: XCTestCase {
    func testVersionIsTheCoreVersion() {
        XCTAssertEqual(PayabliTapToPayModule.version, PayabliCore.version)
    }
}

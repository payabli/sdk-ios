import PayabliSDKCore
import XCTest

final class PayabliSDKCoreTests: XCTestCase {
    func testVersionIsTheCommittedReleaseVersion() {
        XCTAssertNotNil(
            PayabliCore.version.range(of: #"^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$"#, options: .regularExpression),
            PayabliCore.version
        )
        XCTAssertNotEqual(PayabliCore.version, "0.0.0")
    }
}

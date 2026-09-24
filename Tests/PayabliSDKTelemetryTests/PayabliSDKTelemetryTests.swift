import PayabliSDKCore
@testable import PayabliSDKTelemetry
import XCTest

final class PayabliSDKTelemetryTests: XCTestCase {
    func testVersionIsTheCoreVersion() {
        XCTAssertEqual(PayabliSDKTelemetry.version, PayabliCore.version)
    }
}

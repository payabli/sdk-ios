@testable import PayabliSDKTelemetry
import XCTest

final class PayabliSDKTelemetryTests: XCTestCase {
    func testVersionIsPopulated() {
        XCTAssertFalse(PayabliSDKTelemetry.version.isEmpty)
    }
}

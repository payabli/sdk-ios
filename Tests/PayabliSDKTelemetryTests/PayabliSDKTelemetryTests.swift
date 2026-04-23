import XCTest
@testable import PayabliSDKTelemetry

final class PayabliSDKTelemetryTests: XCTestCase {
    func testVersionIsPopulated() {
        XCTAssertFalse(PayabliSDKTelemetry.version.isEmpty)
    }
}

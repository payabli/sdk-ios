import XCTest
import PayabliSDKCore

final class PayabliTransportTests: XCTestCase {
    func testPayabliServiceConformsToPayabliTransport() {
        let service = PayabliService(environment: .sandbox)
        let _: any PayabliTransport = service  // compile-time conformance proof
        XCTAssertTrue(true)
    }
}

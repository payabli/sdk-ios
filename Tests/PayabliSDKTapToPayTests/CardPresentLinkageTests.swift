import PayabliSDKCore
import PayabliSDKTapToPay
import XCTest

/// The positive case can only be asserted where the card-present product is linked, which is here.
final class CardPresentLinkageTests: XCTestCase {
    func testTheNameCoreLooksUpIsTheCardPresentFacade() {
        XCTAssertTrue(NSClassFromString(CardPresentLinkage.module) === PayabliTTP.self)
        XCTAssertTrue(CardPresentLinkage.isLinked)
    }

    func testALinkedAppReportsACardPresentDevice() {
        XCTAssertEqual(TelemetryDeviceFacts.current().deviceType, "Softpos")
    }
}

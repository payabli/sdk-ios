import XCTest
@testable import PayabliSDKTapToPay

final class TapToPayProviderFactoryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TapToPayProviderFactory.shared.resetForTesting()
    }

    override func tearDown() {
        TapToPayProviderFactory.shared.resetForTesting()
        super.tearDown()
    }

    func testRegisterAndBuild() {
        TapToPayProviderFactory.shared.register(providerId: "mock") {
            MockTapToPayProvider()
        }
        XCTAssertTrue(TapToPayProviderFactory.shared.isRegistered("mock"))
        let provider = TapToPayProviderFactory.shared.build(providerId: "mock")
        XCTAssertNotNil(provider)
        XCTAssertTrue(provider is MockTapToPayProvider)
    }

    func testBuildUnknownReturnsNil() {
        XCTAssertNil(TapToPayProviderFactory.shared.build(providerId: "no_such_provider"))
    }
}

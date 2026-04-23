import XCTest
@testable import PayabliSDKPayIn

final class TapToPayProviderFactoryTests: XCTestCase {

    override func setUp() {
        super.setUp()
        TapToPayProviderFactory.shared._reset()
    }

    override func tearDown() {
        TapToPayProviderFactory.shared._reset()
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

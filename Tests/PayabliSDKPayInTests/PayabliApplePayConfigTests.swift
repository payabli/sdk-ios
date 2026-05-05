import XCTest
@testable import PayabliSDKPayIn

final class PayabliApplePayConfigTests: XCTestCase {
    func testDefaultValues() {
        let config = PayabliApplePayConfig(
            merchantIdentifier: "merchant.com.payabli",
            merchantName: "Test Merchant"
        )
        XCTAssertEqual(config.countryCode, "US")
        XCTAssertEqual(config.currencyCode, "USD")
        XCTAssertTrue(config.supports3DS)
        XCTAssertEqual(config.supportedNetworksRaw.sorted(), ["amex", "discover", "masterCard", "visa"])
    }

    func testCustomValues() {
        let config = PayabliApplePayConfig(
            merchantIdentifier: "merchant.ca",
            countryCode: "CA",
            currencyCode: "CAD",
            merchantName: "Maple Co.",
            supports3DS: false,
            supportedNetworks: ["visa"]
        )
        XCTAssertEqual(config.countryCode, "CA")
        XCTAssertEqual(config.currencyCode, "CAD")
        XCTAssertFalse(config.supports3DS)
        XCTAssertEqual(config.supportedNetworksRaw, ["visa"])
    }

    #if canImport(PassKit)
    func testSupportedNetworksResolveToPKPaymentNetworks() {
        let config = PayabliApplePayConfig(
            merchantIdentifier: "m",
            merchantName: "M",
            supportedNetworks: ["visa", "masterCard", "amex", "discover"]
        )
        XCTAssertEqual(config.supportedNetworks.count, 4)
    }
    #endif
}

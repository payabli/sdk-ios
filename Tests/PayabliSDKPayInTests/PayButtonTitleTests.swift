import XCTest
import PayabliSDKCore
@testable import PayabliSDKPayIn

@MainActor
final class PayButtonTitleTests: XCTestCase {
    func testFormatsUSDWithTwoDecimals() {
        let payIn = PayabliPayIn.shared
        let request = PayabliPaymentRequest(totalAmount: 100, currency: "USD")
        let title = payIn.formatPayButtonTitle(request: request)
        // Locale may differ; just assert currency formatting shape.
        XCTAssertTrue(title.contains("100.00"))
        XCTAssertTrue(title.hasPrefix("Pay"))
    }

    func testFormatsDecimalCorrectly() {
        let payIn = PayabliPayIn.shared
        let request = PayabliPaymentRequest(totalAmount: 9.99, currency: "USD")
        let title = payIn.formatPayButtonTitle(request: request)
        XCTAssertTrue(title.contains("9.99"))
    }
}

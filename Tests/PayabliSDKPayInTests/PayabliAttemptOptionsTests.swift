import PayabliSDKCore
import PayabliSDKPayIn
import XCTest

final class PayabliAttemptOptionsTests: XCTestCase {
    func testOptionsAreANewPaymentUnlessTheySayOtherwise() {
        let options = PayabliPayInRequestConfiguration(paymentDetails: PayabliPayInPaymentDetails(totalAmount: 10))

        XCTAssertEqual(options.attempt, .newPayment)
    }

    func testTheFormsRequestCarriesTheDeclaredAttempt() {
        let options = PayabliPayInRequestConfiguration(
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 10),
            attempt: .retry
        )

        let request = options.request(paymentMethod: .cash)

        XCTAssertEqual(request.options.attempt, .retry)
    }
}

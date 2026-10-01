@testable import PayabliSDKPayIn
import XCTest

final class PaymentDetailsValidationTests: XCTestCase {
    private func refusal(_ details: PayabliPayInPaymentDetails) -> String? {
        do {
            try details.validate()
            return nil
        } catch let PayabliPayInError.invalidInput(message) {
            return message
        } catch {
            return "unexpected \(error)"
        }
    }

    func testATotalSentAsZeroIsRefused() {
        XCTAssertEqual(
            refusal(PayabliPayInPaymentDetails(totalAmount: 0.001)),
            "Total amount must be greater than 0."
        )
        XCTAssertEqual(refusal(PayabliPayInPaymentDetails(totalAmount: 0)), "Total amount must be greater than 0.")
    }

    func testTheSmallestTotalSentAsACentIsAccepted() {
        XCTAssertNil(refusal(PayabliPayInPaymentDetails(totalAmount: 0.005)))
        XCTAssertNil(refusal(PayabliPayInPaymentDetails(totalAmount: 0.01)))
    }

    func testEachAmountThatCannotBeSentIsRefusedNamingIt() {
        for unsendable in [Double.infinity, -Double.infinity, .nan, 1e30] {
            XCTAssertEqual(
                refusal(PayabliPayInPaymentDetails(totalAmount: unsendable)),
                "Total amount is out of range."
            )
            XCTAssertEqual(
                refusal(PayabliPayInPaymentDetails(totalAmount: 12.34, serviceFee: unsendable)),
                "Service fee is out of range."
            )
            XCTAssertEqual(
                refusal(PayabliPayInPaymentDetails(totalAmount: 12.34, surchargeFee: unsendable)),
                "Surcharge is out of range."
            )
        }
    }

    func testANegativeFeeIsRefusedAndANegativeSurchargeIsSent() {
        XCTAssertEqual(
            refusal(PayabliPayInPaymentDetails(totalAmount: 12.34, serviceFee: -0.01)),
            "Service fee cannot be negative."
        )
        XCTAssertNil(refusal(PayabliPayInPaymentDetails(totalAmount: 12.34, surchargeFee: -0.31)))
    }

    func testANonFiniteAmountInAdditionalDataIsRefusedNotSent() {
        for text in ["inf", "nan", "-inf"] {
            let body: [String: Any] = ["customerData": ["additionalData": ["surchargeFee": text]]]

            XCTAssertThrowsError(try PayInPaymentFlowJSONBody.normalizingCurrencyFields(in: body)) { error in
                guard case PayabliPayInError.invalidInput = error else {
                    return XCTFail("expected invalidInput, got \(error)")
                }
            }
        }
    }

    func testASendableAmountIsWrittenAtTwoPlaces() throws {
        let body: [String: Any] = ["paymentDetails": ["totalAmount": 12.345, "serviceFee": 0.1]]
        let data = try PayInPaymentFlowJSONBody.data(from: PayInPaymentFlowJSONBody.normalizingCurrencyFields(in: body))

        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"paymentDetails":{"serviceFee":0.10,"totalAmount":12.35}}"#)
    }
}

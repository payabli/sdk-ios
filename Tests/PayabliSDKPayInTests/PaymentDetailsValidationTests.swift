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

    func testAdditionalDataIsSentAsTheHostGaveItWhateverItsKeysAreCalled() throws {
        for value in ["12.345", "9007199254740993.01", "inf", "0x10", true, 1e30] as [Any] {
            let body: [String: Any] = ["customerData": ["additionalData": ["totalAmount": value]]]
            let normalized = try PayInPaymentFlowJSONBody.normalizingCurrencyFields(in: body)
            let customer = try XCTUnwrap((normalized as? [String: Any])?["customerData"] as? [String: Any])
            let additional = try XCTUnwrap(customer["additionalData"] as? [String: Any])

            XCTAssertEqual(String(describing: additional["totalAmount"] ?? ""), String(describing: value))
        }
    }

    func testAPaymentAmountThatCannotBeSentIsRefusedNamingIt() {
        let body: [String: Any] = ["paymentDetails": ["totalAmount": 1e30]]

        XCTAssertThrowsError(try PayInPaymentFlowJSONBody.normalizingCurrencyFields(in: body)) { error in
            XCTAssertEqual(error as? PayabliPayInError, .invalidInput("paymentDetails.totalAmount is out of range."))
        }
    }

    func testATieIsRoundedAsTheDecimalItWasWrittenAs() throws {
        XCTAssertEqual(PayInAmount.sendable(1.005), Decimal(string: "1.01"))
        XCTAssertEqual(PayInAmount.sendable(0.235), Decimal(string: "0.24"))

        let body: [String: Any] = ["paymentDetails": ["totalAmount": 2.005]]
        let data = try PayInPaymentFlowJSONBody.data(from: PayInPaymentFlowJSONBody.normalizingCurrencyFields(in: body))
        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"paymentDetails":{"totalAmount":2.01}}"#)
    }

    func testASendableAmountIsWrittenAtTwoPlaces() throws {
        let body: [String: Any] = ["paymentDetails": ["totalAmount": 12.345, "serviceFee": 0.1]]
        let data = try PayInPaymentFlowJSONBody.data(from: PayInPaymentFlowJSONBody.normalizingCurrencyFields(in: body))

        XCTAssertEqual(String(data: data, encoding: .utf8), #"{"paymentDetails":{"serviceFee":0.10,"totalAmount":12.35}}"#)
    }
}

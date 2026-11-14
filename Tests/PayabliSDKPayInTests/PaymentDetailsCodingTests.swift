import PayabliSDKCore
import PayabliSDKPayIn
import XCTest

final class PaymentDetailsCodingTests: XCTestCase {
    private func decode(_ json: String) throws -> PayabliPayInPaymentDetails {
        try JSONDecoder().decode(PayabliPayInPaymentDetails.self, from: Data(json.utf8))
    }

    private func encoded(_ details: PayabliPayInPaymentDetails) throws -> [String: Any] {
        let data = try JSONEncoder().encode(details)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testTheCurrencyIsWrittenAsItsCode() throws {
        let json = try encoded(PayabliPayInPaymentDetails(totalAmount: 1, currency: .usd))

        XCTAssertEqual(json["currency"] as? String, "USD")
    }

    func testACurrencyCodeReadsAsItsCurrency() throws {
        XCTAssertEqual(try decode(#"{"totalAmount":1,"currency":"USD"}"#).currency, .usd)
    }

    func testAbsentCurrencyReadsAsNone() throws {
        XCTAssertNil(try decode(#"{"totalAmount":1}"#).currency)
    }

    func testACodeNoCurrencyHasIsRefused() {
        for code in ["AUD", "usd", ""] {
            XCTAssertThrowsError(try decode(#"{"totalAmount":1,"currency":"\#(code)"}"#), code) { error in
                guard case DecodingError.dataCorrupted = error else {
                    return XCTFail("\(code): \(error)")
                }
            }
        }
    }

    func testEveryFieldSurvivesARoundTrip() throws {
        let details = PayabliPayInPaymentDetails(
            totalAmount: 12.34,
            serviceFee: 0.5,
            surchargeFee: 0.31,
            currency: .usd,
            checkNumber: "101",
            checkUniqueId: "c-1"
        )

        let read = try JSONDecoder().decode(PayabliPayInPaymentDetails.self, from: JSONEncoder().encode(details))

        XCTAssertEqual(read, details)
    }
}

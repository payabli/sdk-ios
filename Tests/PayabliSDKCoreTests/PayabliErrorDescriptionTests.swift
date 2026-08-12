import PayabliSDKCore
import XCTest

/// `localizedDescription` is what a host app shows a merchant. These guard the
/// case that shipped: an enum conforming only to `Error` renders as its case
/// index, so a parsed reason never reached the screen.
final class PayabliErrorDescriptionTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(type, from: Data(json.utf8))
    }

    func testPaymentErrorDoesNotRenderAsACaseIndex() {
        let error = PayabliPaymentError.generic(
            PayabliGenericError(code: .networkError, reason: "Could not reach the host")
        )

        let message = (error as Error).localizedDescription

        XCTAssertEqual(message, "Could not reach the host")
        XCTAssertFalse(message.contains("error 3"), "the case index must not be what a merchant reads")
    }

    func testGenericErrorJoinsReasonAndDetail() {
        let error = PayabliGenericError(
            code: .invalidConfiguration,
            reason: "Missing entry point",
            detail: "Set entryPoint on PayabliConfig"
        )

        XCTAssertEqual(
            (error as Error).localizedDescription,
            "Missing entry point: Set entryPoint on PayabliConfig"
        )
    }

    func testValidationErrorNamesTheRejectedFields() throws {
        let error = try decode(PayabliValidationError.self, """
        {
          "title": "Validation failed",
          "status": 400,
          "errors": {
            "paymentMethod.cardexp": [{"message": "is not a valid expiration"}],
            "customerData": [{"message": "is required"}]
          }
        }
        """)

        let message = (PayabliPaymentError.validation(error) as Error).localizedDescription

        XCTAssertTrue(message.contains("customerData: is required"), message)
        XCTAssertTrue(message.contains("paymentMethod.cardexp: is not a valid expiration"), message)
    }

    func testValidationErrorWithoutFieldsStillReadsAsTheTitle() throws {
        let error = try decode(PayabliValidationError.self, #"{"title": "Amount too small"}"#)

        XCTAssertEqual(
            (PayabliPaymentError.validation(error) as Error).localizedDescription,
            "Amount too small"
        )
    }

    func testDeclineErrorCarriesTheActionThePayerCanTake() throws {
        let error = try decode(PayabliDeclineError.self, """
        {"code": "850", "reason": "Declined", "explanation": "AVS or CVV failed", "action": "Try another card"}
        """)

        XCTAssertEqual(
            (PayabliPaymentError.decline(error) as Error).localizedDescription,
            "Declined · AVS or CVV failed · Try another card"
        )
    }
}

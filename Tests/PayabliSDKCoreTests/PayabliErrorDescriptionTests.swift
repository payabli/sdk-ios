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

    /// `mapPayabliHTTPError` throws this umbrella, so every `error as? any
    /// PayabliError` in the SDK, in a host app and in this SDK's documentation
    /// depends on it conforming.
    func testTheUmbrellaAnswersTheWrappedErrorsCode() throws {
        let validation = try decode(PayabliValidationError.self, """
        {"title": "Validation failed", "status": 400}
        """)

        let umbrella: Error = PayabliPaymentError.validation(validation)

        XCTAssertEqual((umbrella as? any PayabliError)?.code, .validation)
        XCTAssertEqual((umbrella as? any PayabliError)?.reason, "Validation failed")
    }

    /// The fallback the conformance removes. Without it these paths reached
    /// `String(describing:)`, which renders every stored property of the wrapped
    /// error, `token` included, and the SDK puts that string on a screen.
    func testTheUmbrellaNeverFallsBackToADumpOfItsFields() throws {
        let validation = try decode(PayabliValidationError.self, """
        {"title": "Validation failed", "status": 400, "token": "page-token-9f2"}
        """)

        let umbrella: Error = PayabliPaymentError.validation(validation)
        let described = (umbrella as? any PayabliError)?.reason ?? String(describing: umbrella)

        XCTAssertFalse(described.contains("page-token-9f2"), described)
    }

    func testValidationErrorNamesTheRejectedFields() throws {
        let error = try decode(PayabliValidationError.self, """
        {
          "title": "Validation failed",
          "status": 400,
          "errors": {
            "paymentMethod.cardexp": [
              {"message": "is not a valid expiration", "suggestion": "try 12/2029"}
            ],
            "customerData": [{"message": "is required"}]
          }
        }
        """)

        let message = (PayabliPaymentError.validation(error) as Error).localizedDescription

        XCTAssertTrue(message.contains("customerData: is required"), message)
        XCTAssertTrue(message.contains("paymentMethod.cardexp: is not a valid expiration"), message)

        // A suggestion can quote a corrected value, so it stays out of the string a
        // host app displays and logs.
        XCTAssertFalse(message.contains("12/2029"), message)
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

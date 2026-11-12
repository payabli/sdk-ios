@testable import PayabliSDKCore
import XCTest

final class PayabliValidationErrorInitTests: XCTestCase {
    func testEveryParameterReadsBack() {
        let field = PayabliFieldError(message: "Card number is invalid.", suggestion: "Check the digits.")
        let err = PayabliValidationError(
            httpStatus: 400,
            reason: "One or more validation errors occurred.",
            detail: "The card was refused.",
            rawCode: "E0001",
            errors: ["paymentMethod.cardnumber": [field]]
        )

        XCTAssertEqual(err.httpStatus, 400)
        XCTAssertEqual(err.reason, "One or more validation errors occurred.")
        XCTAssertEqual(err.detail, "The card was refused.")
        XCTAssertEqual(err.rawCode, "E0001")
        XCTAssertEqual(err.errors["paymentMethod.cardnumber"]?.first?.message, "Card number is invalid.")
        XCTAssertEqual(err.errors["paymentMethod.cardnumber"]?.first?.suggestion, "Check the digits.")
        XCTAssertEqual(err.type, .validation)
    }

    func testOnlyTheStatusTakesTheDefaults() {
        let err = PayabliValidationError(httpStatus: 422)

        XCTAssertEqual(err.httpStatus, 422)
        XCTAssertEqual(err.reason, "Validation failed")
        XCTAssertNil(err.detail)
        XCTAssertNil(err.rawCode)
        XCTAssertTrue(err.errors.isEmpty)
        XCTAssertEqual(err.type, .validation)
    }

    func testAFieldErrorWithoutASuggestion() {
        let field = PayabliFieldError(message: "Required.")

        XCTAssertEqual(field.message, "Required.")
        XCTAssertNil(field.suggestion)
    }

    func testABuiltErrorDescribesItselfAsTheDecodedOneDoes() throws {
        let json = """
        {"title":"Bad Request","detail":"Fix the card.","code":"E0001",
         "errors":{"b":[{"message":"second"}],"a":["first"]}}
        """
        let decoded = try JSONDecoder().decode(PayabliValidationError.self, from: Data(json.utf8))
            .carrying(httpStatus: 400, rawCode: "E0001")
        let built = PayabliValidationError(
            httpStatus: 400,
            reason: "Bad Request",
            detail: "Fix the card.",
            rawCode: "E0001",
            errors: ["a": [PayabliFieldError(message: "first")], "b": [PayabliFieldError(message: "second")]]
        )

        XCTAssertEqual(built.errorDescription, decoded.errorDescription)
        XCTAssertEqual(built.errorDescription, "Bad Request · Fix the card. · a: first · b: second")
    }

    func testABodyNamingNoFieldDecodesToNoFields() throws {
        let err = try JSONDecoder().decode(PayabliValidationError.self, from: Data(#"{"title":"Bad Request"}"#.utf8))

        XCTAssertTrue(err.errors.isEmpty)
        XCTAssertEqual(err.reason, "Bad Request")
    }

    func testABodyWithoutATitleTakesTheDefaultReason() throws {
        let err = try JSONDecoder().decode(PayabliValidationError.self, from: Data(#"{"detail":"x"}"#.utf8))

        XCTAssertEqual(err.reason, "Validation failed")
    }

    func testAServerErrorReadsItsReasonFromTheTitle() throws {
        let err = try JSONDecoder().decode(PayabliServerError.self, from: Data(#"{"title":"Gateway down"}"#.utf8))

        XCTAssertEqual(err.reason, "Gateway down")
    }
}

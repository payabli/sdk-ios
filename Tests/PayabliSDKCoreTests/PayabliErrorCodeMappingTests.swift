import XCTest
@testable import PayabliSDKCore

final class PayabliErrorCodeMappingTests: XCTestCase {

    func testValidationErrorCodeMapsToValidation() throws {
        // Construct a PayabliValidationError via JSON decoding (the only
        // way to build one — it has no public memberwise init).
        let json = """
        {
          "title": "Bad Request",
          "status": 400,
          "detail": "One or more validation errors occurred.",
          "instance": "/api/v2/MoneyIn/getpaid",
          "code": "E0001"
        }
        """.data(using: .utf8)!

        let err = try JSONDecoder().decode(PayabliValidationError.self, from: json)
        XCTAssertEqual(
            err.code,
            .validation,
            "PayabliValidationError.code must be .validation, not .decodingError"
        )
        XCTAssertEqual(err.rawCode, "E0001")
        XCTAssertEqual(err.title, "Bad Request")
    }
}

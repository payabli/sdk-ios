import PayabliSDKCore
import XCTest

final class PayabliErrorCodeMappingTests: XCTestCase {
    func testValidationErrorCodeMapsToValidation() throws {
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
            err.type,
            .validation,
            "PayabliValidationError.type must be .validation, not .decodingError"
        )
        XCTAssertEqual(err.rawCode, "E0001")
        XCTAssertEqual(err.reason, "Bad Request")
    }
}

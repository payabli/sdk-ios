import PayabliSDKCore
import XCTest

final class PayabliErrorStatusTests: XCTestCase {
    /// A conformer of its own, as a component may write, that declares neither property.
    private struct ComponentError: PayabliError {
        var type: PayabliErrorType {
            .unknown
        }

        var reason: String {
            "component"
        }

        var detail: String? {
            nil
        }
    }

    func testAConformerThatDeclaresNeitherReadsNilForBoth() {
        let error: any PayabliError = ComponentError()

        XCTAssertNil(error.httpStatus)
        XCTAssertNil(error.rawCode)
    }

    func testAGenericErrorBuiltWithoutAnAnswerCarriesNeither() {
        let error: any PayabliError = PayabliGenericError(type: .networkError, reason: "offline")

        XCTAssertNil(error.httpStatus)
        XCTAssertNil(error.rawCode)
    }

    func testAGenericErrorBuiltFromAnAnswerCarriesItsStatusAndCode() {
        let error: any PayabliError = PayabliGenericError(
            type: .unknown,
            reason: "HTTP 418",
            httpStatus: 418,
            rawCode: "E1001"
        )

        XCTAssertEqual(error.httpStatus, 418)
        XCTAssertEqual(error.rawCode, "E1001")
    }
}

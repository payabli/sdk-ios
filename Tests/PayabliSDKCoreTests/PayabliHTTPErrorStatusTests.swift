import PayabliSDKCore
import XCTest

/// What the mapper hands over beside the classification: the status line, and the code the body named.
final class PayabliHTTPErrorStatusTests: XCTestCase {
    func testAnUnmappedStatusCarriesItsStatusAndTheBodysCode() throws {
        let error = try mapped(status: 418, body: #"{"code":"E1001"}"#)

        XCTAssertEqual(error.type, .unknown)
        XCTAssertEqual(error.httpStatus, 418)
        XCTAssertEqual(error.rawCode, "E1001")
    }

    func testAnUnmappedStatusWithAnUnreadableBodyKeepsItsStatus() throws {
        let error = try mapped(status: 418, body: "<html>teapot</html>")

        XCTAssertEqual(error.type, .unknown)
        XCTAssertEqual(error.httpStatus, 418)
        XCTAssertNil(error.rawCode)
    }

    func testAValidationErrorTakesTheStatusLineNotTheBodysStatus() throws {
        let error = try mapped(status: 400, body: #"{"title":"Bad","status":422,"code":"E2001"}"#)

        XCTAssertEqual(error.type, .validation)
        XCTAssertEqual(error.httpStatus, 400)
        XCTAssertEqual(error.rawCode, "E2001")
    }

    func testAValidationBodyTheTypedShapeCannotReadStillGivesItsCode() throws {
        let error = try mapped(status: 400, body: #"{"status":"bad","code":"E2002"}"#)

        XCTAssertEqual(error.type, .validation)
        XCTAssertEqual(error.httpStatus, 400)
        XCTAssertEqual(error.rawCode, "E2002")
    }

    func testADeclineCarriesItsStatusAndCode() throws {
        let error = try mapped(status: 402, body: #"{"code":"D0329","reason":"Declined"}"#)

        XCTAssertEqual(error.type, .paymentDeclined)
        XCTAssertEqual(error.httpStatus, 402)
        XCTAssertEqual(error.rawCode, "D0329")
    }

    func testAServerErrorCarriesItsStatusAndCode() throws {
        let error = try mapped(status: 503, body: #"{"title":"Down","status":500,"code":"E5001"}"#)

        XCTAssertEqual(error.type, .serverError)
        XCTAssertEqual(error.httpStatus, 503)
        XCTAssertEqual(error.rawCode, "E5001")
    }

    func testARateLimitCarriesItsStatusAndCode() throws {
        let error = try mapped(status: 429, body: #"{"code":"E4290"}"#)

        XCTAssertEqual(error.type, .rateLimited)
        XCTAssertEqual(error.httpStatus, 429)
        XCTAssertEqual(error.rawCode, "E4290")
    }

    func testEveryStatusTheMapperNamesCarriesItsStatus() throws {
        for status in [401, 403, 408, 409, 410] {
            let error = try mapped(status: status, body: #"{"code":"E\#(status)"}"#)

            XCTAssertEqual(error.httpStatus, status, "status \(status)")
            XCTAssertEqual(error.rawCode, "E\(status)", "status \(status)")
        }
    }

    func testACodeThatIsNotAStringIsLeftOut() throws {
        let error = try mapped(status: 418, body: #"{"code":9005}"#)

        XCTAssertEqual(error.httpStatus, 418)
        XCTAssertNil(error.rawCode)
    }

    func testAnOlderEnvelopeGivesItsResponseCodeAsTheCode() throws {
        let error = try mapped(status: 400, body: #"{"isSuccess":false,"responseText":"Declined","responseCode":9005}"#)

        XCTAssertEqual(error.httpStatus, 400)
        XCTAssertEqual(error.rawCode, "9005")
    }

    func testABodyWithNeitherCodeGivesNone() throws {
        let error = try mapped(status: 400, body: #"{"responseText":"Bad request"}"#)

        XCTAssertNil(error.rawCode)
    }

    func testTheBodysCodeIsPreferredOverResponseCode() throws {
        let error = try mapped(status: 400, body: #"{"code":"E2001","responseCode":9005}"#)

        XCTAssertEqual(error.rawCode, "E2001")
    }

    func testAMalformedCodeDoesNotLoseTheResponseCode() throws {
        let error = try mapped(status: 400, body: #"{"code":{"bad":true},"responseCode":9005}"#)

        XCTAssertEqual(error.rawCode, "9005")
    }

    func testAMalformedDisplayFieldDoesNotLoseTheCode() throws {
        let error = try mapped(status: 404, body: #"{"title":42,"detail":[1],"code":"E0404"}"#)

        XCTAssertEqual(error.httpStatus, 404)
        XCTAssertEqual(error.rawCode, "E0404")
    }

    func testAQuotedResponseCodeIsReadAsTheCode() throws {
        let error = try mapped(status: 400, body: #"{"responseCode":"9001"}"#)

        XCTAssertEqual(error.rawCode, "9001")
    }

    func testANumericCodeDoesNotLoseAServerErrorsBody() throws {
        let error = try mapped(status: 500, body: #"{"title":"Down","detail":"Try later","code":5001}"#)

        XCTAssertEqual(error.type, .serverError)
        XCTAssertEqual(error.detail, "Try later")
        XCTAssertEqual(error.httpStatus, 500)
    }

    func testANumericCodeDoesNotLoseAValidationBody() throws {
        let error = try mapped(status: 400, body: #"{"title":"Bad","detail":"Amount is required","code":2001}"#)

        XCTAssertEqual(error.type, .validation)
        XCTAssertEqual(error.detail, "Amount is required")
    }

    func testANumericCodeDoesNotLoseADeclineBody() throws {
        let error = try mapped(status: 402, body: #"{"reason":"Declined","explanation":"Insufficient funds","code":329}"#)

        XCTAssertEqual(error.type, .paymentDeclined)
        XCTAssertEqual(error.detail, "Insufficient funds")
    }

    private func mapped(status: Int, body: String) throws -> any PayabliError {
        let response = PayabliResponse(statusCode: status, headers: [:], body: Data(body.utf8))
        do {
            try mapPayabliHTTPError(response: response)
        } catch let error as any PayabliError {
            return error
        }
        XCTFail("status \(status) mapped to no error")
        throw CancellationError()
    }
}

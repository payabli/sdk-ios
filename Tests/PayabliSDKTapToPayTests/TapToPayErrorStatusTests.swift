@testable import PayabliSDKCore
@testable import PayabliSDKTapToPay
import XCTest

/// A card-present failure read from an answer reaches a host carrying that answer's status and code.
@available(iOS 16.7, *)
final class TapToPayErrorStatusTests: XCTestCase {
    func testARefusedOpeningCarriesItsAnswersStatusAndCode() async throws {
        let host = try await initiateFailure(status: 200, body: #"{"code":"E3001","reason":"Not allowed","data":null}"#)

        XCTAssertEqual(host.type, .paymentNotOpened)
        XCTAssertEqual(host.httpStatus, 200)
        XCTAssertEqual(host.rawCode, "E3001")
    }

    func testARefusedCustomerCarriesItsAnswersStatusAndCode() async throws {
        let message = "Missing customer identifiers: Email"
        let body = """
        {"title":"Bad Request","status":422,"code":"E7020","errors":{"customerData":[{"message":"\(message)"}]}}
        """

        let host = try await initiateFailure(status: 400, body: body)

        XCTAssertEqual(host.type, .validation)
        XCTAssertEqual(host.httpStatus, 400)
        XCTAssertEqual(host.rawCode, "E7020")
    }

    func testARefusedChargeKeyCarriesTheConflictsStatus() async throws {
        let host = try await initiateFailure(status: 409, body: "")

        XCTAssertEqual(host.type, .conflict)
        XCTAssertEqual(host.httpStatus, 409)
        XCTAssertNil(host.rawCode)
    }

    func testACoreErrorReadFromAnAnswerKeepsItsStatusAndCode() async throws {
        let host = try await initiateFailure(status: 503, body: #"{"title":"Down","code":"E5001"}"#)

        XCTAssertEqual(host.type, .serverError)
        XCTAssertEqual(host.httpStatus, 503)
        XCTAssertEqual(host.rawCode, "E5001")
    }

    func testAPaypointNotEnabledOnTheOpeningCarriesTheStatusAndTheBodysCode() async throws {
        let host = try await initiateFailure(status: 404, body: #"{"code":"E0404"}"#)

        XCTAssertEqual(host.type, .cardPresentNotEnabled)
        XCTAssertEqual(host.httpStatus, 404)
        XCTAssertEqual(host.rawCode, "E0404")
    }

    func testAnOpeningAnswerThatCannotBeReadCarriesItsStatus() async throws {
        let host = try await initiateFailure(status: 200, body: "not json")

        XCTAssertEqual(host.type, .decodingError)
        XCTAssertEqual(host.httpStatus, 200)
        XCTAssertNil(host.rawCode)
    }

    func testAnApprovedOpeningWithNoPaymentCarriesItsStatusAndCode() async throws {
        let host = try await initiateFailure(status: 200, body: #"{"code":"A01","data":null}"#)

        XCTAssertEqual(host.type, .decodingError)
        XCTAssertEqual(host.httpStatus, 200)
        XCTAssertEqual(host.rawCode, "A01")
    }

    func testAPinnedTokenRefusalCarriesItsStatus() throws {
        let host = try XCTUnwrap(TapToPayErrorTranslation.hostError(for: PinnedTokenRefusal()) as? TapToPayError)

        XCTAssertEqual(host.httpStatus, 401)
    }

    func testAStatusAndACodeAlwaysComeFromOneAnswer() throws {
        let answered = PayabliGenericError(type: .unknown, reason: "HTTP 418", httpStatus: 418, rawCode: "E1001")
        let wrapper = PayabliGenericError(type: .unknown, reason: "outer", underlying: answered)

        let host = try XCTUnwrap(TapToPayErrorTranslation.hostError(for: wrapper) as? TapToPayError)

        XCTAssertEqual(host.httpStatus, 418)
        XCTAssertEqual(host.rawCode, "E1001")
    }

    func testAFailureNoAnswerWasReadForCarriesNeither() throws {
        let host = try XCTUnwrap(TapToPayErrorTranslation.hostError(for: PayabliTTPError.notInitialized) as? TapToPayError)

        XCTAssertNil(host.httpStatus)
        XCTAssertNil(host.rawCode)
    }

    func testAChargesFailureKeepsItsStatusAndCodeWhenItsTypeChanges() throws {
        let refused = PayabliTTPError.paymentNotOpened(reason: "x", httpStatus: 200, rawCode: "E3001")

        let host = try XCTUnwrap(
            TapToPayErrorTranslation.hostError(for: refused, chargeOf: "pay-1", askedForCard: true) as? TapToPayError
        )

        XCTAssertEqual(host.httpStatus, 200)
        XCTAssertEqual(host.rawCode, "E3001")
    }

    // MARK: - Fixtures

    private func initiateFailure(status: Int, body: String) async throws -> TapToPayError {
        let client = TTPTransactionClient(transport: AnsweringTransport(status: status, body: body))
        do {
            _ = try await client.initiate(
                entryPoint: "myEntry",
                deviceId: "dev_1",
                idempotencyKey: "key-1",
                paymentDetails: PayabliTTPPaymentDetails(amount: 1, currency: "USD")
            )
        } catch {
            return try XCTUnwrap(TapToPayErrorTranslation.hostError(for: error) as? TapToPayError, "\(error)")
        }
        XCTFail("initiate succeeded")
        throw CancellationError()
    }
}

/// Answers every request with one status and body.
private struct AnsweringTransport: PayabliTransport {
    let status: Int
    let body: String

    func perform(_: PayabliRequest) async throws -> PayabliResponse {
        PayabliResponse(statusCode: status, headers: [:], body: Data(body.utf8))
    }

    func performV2<T: Decodable & Sendable>(_: PayabliRequest, decoding _: T.Type) async throws -> PayabliV2Envelope<T> {
        try JSONDecoder().decode(PayabliV2Envelope<T>.self, from: Data(body.utf8))
    }
}

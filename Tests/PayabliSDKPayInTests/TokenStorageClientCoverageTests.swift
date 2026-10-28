import Foundation
@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

final class TokenStorageClientCoverageTests: XCTestCase {
    override func setUp() {
        super.setUp()
        PayInKeyStore.process.forgetHeld()
    }

    func testAStoreBadRequestCarriesTheRoutesResponseTextInItsDetail() async throws {
        let transport = CoverageMockTransport(statusCode: 400, responseBody: """
        { "responseText": "Paypoint not found or inactive" }
        """)
        let client = PayInPaymentFlowTokenStorageClient(transport: transport)

        do {
            _ = try await client.addMethod(
                entryPoint: "entry",
                paymentMethod: .card(PayabliPayInCardData(
                    cardNumber: "4111111111111111",
                    expiration: "02/28",
                    cardholderName: "Jane Doe",
                    cvv: "123",
                    billingZip: "33139"
                ))
            )
            XCTFail("Expected a validation error")
        } catch let PayabliPaymentError.validation(validation) {
            XCTAssertEqual(validation.detail, "Paypoint not found or inactive")
            XCTAssertNil(validation.errors, "the route names no field, so none is invented")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testAFailedAddSendsItsQueryAndSurfacesTheTransportError() async throws {
        let transport = CoverageFailingTransport(error: PayabliGenericError(
            type: .networkError,
            reason: "Offline"
        ))
        let client = PayInPaymentFlowTokenStorageClient(transport: transport)

        do {
            _ = try await client.addMethod(
                entryPoint: "entry",
                paymentMethod: .card(PayabliPayInCardData(
                    cardNumber: "4111111111111111",
                    expiration: "02/28",
                    cardholderName: "Jane Doe",
                    cvv: "123",
                    billingZip: "33139"
                )),
                options: PayabliPayInOptions(
                    createAnonymous: false,
                    temporary: true
                )
            )
            XCTFail("Expected transport error")
        } catch let error as PayabliGenericError {
            XCTAssertEqual(error.type, .networkError)
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        let requests = await transport.requests
        let request = try XCTUnwrap(requests.first)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/api/TokenStorage/add")
        XCTAssertTrue(request.query.contains(URLQueryItem(name: "createAnonymous", value: "false")))
        XCTAssertTrue(request.query.contains(URLQueryItem(name: "temporary", value: "true")))
        XCTAssertFalse(request.headers.keys.contains { $0.lowercased() == "authorization" })
    }

    func testArrayAndNonJSONResponsesAreDecodingErrors() async throws {
        let arrayTransport = CoverageMockTransport(responseBody: """
        [
          {
            "cardNumber": "4111111111111111",
            "billingEmail": "jane@example.com",
            "resultText": "Visible"
          }
        ]
        """)
        let arrayClient = PayInPaymentFlowTokenStorageClient(transport: arrayTransport)

        do {
            _ = try await arrayClient.addMethod(
                entryPoint: "entry",
                paymentMethod: .card(PayabliPayInCardData(
                    cardNumber: "4111111111111111",
                    expiration: "02/28",
                    cardholderName: "Jane Doe",
                    cvv: "123",
                    billingZip: "33139"
                ))
            )
            XCTFail("Expected decoding error")
        } catch let error as PayabliGenericError {
            XCTAssertEqual(error.type, .decodingError)
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        let nonJSONTransport = CoverageMockTransport(responseBody: "gateway text response")
        let nonJSONClient = PayInPaymentFlowTokenStorageClient(transport: nonJSONTransport)

        do {
            _ = try await nonJSONClient.addMethod(
                entryPoint: "entry",
                paymentMethod: .card(PayabliPayInCardData(
                    cardNumber: "4111111111111111",
                    expiration: "02/28",
                    cardholderName: "Jane Doe",
                    cvv: "123",
                    billingZip: "33139"
                ))
            )
            XCTFail("Expected decoding error")
        } catch let error as PayabliGenericError {
            XCTAssertEqual(error.type, .decodingError)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testApprovedResultCodeWithoutSuccessFlagDecodesStoredMethod() async throws {
        let transport = CoverageMockTransport(responseBody: """
        {
          "responseText": "Success",
          "responseData": {
            "referenceId": "stored-result-code",
            "resultCode": 1,
            "resultText": "Approved"
          }
        }
        """)
        let client = PayInPaymentFlowTokenStorageClient(
            transport: transport
        )

        let result = try await client.addMethod(
            entryPoint: "entry",
            paymentMethod: .card(PayabliPayInCardData(
                cardNumber: "4111111111111111",
                expiration: "02/28",
                cardholderName: "Jane Doe",
                cvv: "123",
                billingZip: "33139"
            ))
        )

        XCTAssertEqual(result.storedMethodId, "stored-result-code")
        XCTAssertEqual(result.resultCode, 1)
    }

    func testA200ThatClaimsNothingIsARefusalRatherThanAStoredMethod() async throws {
        let transport = CoverageMockTransport(responseBody: """
        { "responseText": "Success" }
        """)
        let client = PayInPaymentFlowTokenStorageClient(transport: transport)

        do {
            _ = try await client.addMethod(
                entryPoint: "entry",
                paymentMethod: .card(PayabliPayInCardData(
                    cardNumber: "4111111111111111",
                    expiration: "02/28",
                    cardholderName: "Jane Doe",
                    cvv: "123",
                    billingZip: "33139"
                ))
            )
            XCTFail("Expected a refusal")
        } catch let error as PayabliPayInTokenStorageError {
            guard case .saveFailed = error else { return XCTFail("Wrong error: \(error)") }
            XCTAssertEqual(error.type, .paymentDeclined)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testUnapprovedResultCodeWithoutFailureFlagThrowsSaveFailure() async throws {
        let transport = CoverageMockTransport(responseBody: """
        {
          "responseText": "Gateway response",
          "responseData": {
            "resultCode": 2,
            "resultText": "Processor declined"
          }
        }
        """)
        let client = PayInPaymentFlowTokenStorageClient(
            transport: transport
        )

        do {
            _ = try await client.addMethod(
                entryPoint: "entry",
                paymentMethod: .card(PayabliPayInCardData(
                    cardNumber: "4111111111111111",
                    expiration: "02/28",
                    cardholderName: "Jane Doe",
                    cvv: "123",
                    billingZip: "33139"
                ))
            )
            XCTFail("Expected save failure")
        } catch let PayabliPayInTokenStorageError.saveFailed(failure) {
            XCTAssertEqual(failure.responseText, "Gateway response")
            XCTAssertEqual(failure.resultCode, 2)
            XCTAssertEqual(failure.resultText, "Processor declined")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testAnInvalidEntryPointDoesNotReachTransport() async throws {
        let invalidEntryTransport = CoverageMockTransport(responseBody: "{}")
        let invalidEntryClient = PayInPaymentFlowTokenStorageClient(
            transport: invalidEntryTransport
        )

        do {
            _ = try await invalidEntryClient.addMethod(
                entryPoint: "   ",
                paymentMethod: .card(PayabliPayInCardData(
                    cardNumber: "4111111111111111",
                    expiration: "02/28",
                    cardholderName: "Jane Doe",
                    cvv: "123",
                    billingZip: "33139"
                ))
            )
            XCTFail("Expected invalid entrypoint error")
        } catch let PayabliPayInTokenStorageError.invalidInput(message) {
            XCTAssertEqual(message, "Entrypoint is required.")
            let requests = await invalidEntryTransport.requests
            XCTAssertTrue(requests.isEmpty)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    /// A blank token is refused, and this surface answers in its own error type.
    ///
    /// The token is checked where it is installed, which is the session's holder, so the refusal
    /// carries the holder's vocabulary rather than this surface's. Driven through the facade's own
    /// transport, because injecting a double replaces the chain and never reads a credential.
    @MainActor
    func testABlankTokenIsRefusedByTheHolder() async throws {
        let component = flowOnSession(token: "")

        do {
            _ = try await component.addCard(PayabliPayInCardData(
                cardNumber: "4111111111111111",
                expiration: "02/28",
                cardholderName: "Jane Doe",
                cvv: "123",
                billingZip: "33139"
            ))
            XCTFail("Expected missing token error")
        } catch let error as PayabliGenericError {
            XCTAssertEqual(error.type, .tokenProviderFailed)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    @MainActor
    func testACHViewModelDefaultsNilHiddenSecCodeToWeb() async throws {
        let transport = CoverageMockTransport(responseBody: """
        {
          "responseText": "Success",
          "isSuccess": true,
          "responseData": {
            "referenceId": "ach-default-hidden-sec",
            "resultCode": 1,
            "resultText": "Approved",
            "methodReferenceId": "ach-default-hidden-sec"
          }
        }
        """)
        let viewModel = PayabliPayInViewModel(
            component: PayabliPayIn(
                entryPoint: "entry-ach-hidden",
                environment: .sandbox,
                transport: transport
            ),
            configuration: PayabliPayInFormConfiguration(
                allowedMethods: [.bankAccount],
                defaultMethod: .bankAccount,
                hiddenValues: PayabliPayInHiddenValues(secCode: nil)
            )
        )
        viewModel.accountHolder = "Jane Business"
        viewModel.routingNumber = "123456780"
        viewModel.accountNumber = "1111111111111"

        _ = try await viewModel.submit()

        let request = try await coverageFirstRequest(from: transport)
        let body = try coverageParseBody(request)
        let paymentMethod = try XCTUnwrap(body["paymentMethod"] as? [String: Any])
        XCTAssertEqual(paymentMethod["achCode"] as? String, "WEB")
    }
}

private func coverageParseBody(_ request: PayabliRequest) throws -> [String: Any] {
    let body = try XCTUnwrap(request.body)
    return try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
}

private func coverageFirstRequest(from transport: CoverageMockTransport) async throws -> PayabliRequest {
    let requests = await transport.requests
    return try XCTUnwrap(requests.first)
}

private actor CoverageMockTransport: PayabliTransport {
    private let statusCode: Int
    private let responseBody: String
    private(set) var requests: [PayabliRequest] = []

    init(statusCode: Int = 200, responseBody: String) {
        self.statusCode = statusCode
        self.responseBody = responseBody
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        requests.append(request)
        return PayabliResponse(
            statusCode: statusCode,
            headers: [:],
            body: Data(responseBody.utf8)
        )
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        throw PayabliGenericError(type: .unknown, reason: "performV2 is not used")
    }
}

private actor CoverageFailingTransport: PayabliTransport {
    private let error: Error
    private(set) var requests: [PayabliRequest] = []

    init(error: Error) {
        self.error = error
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        requests.append(request)
        throw error
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        throw PayabliGenericError(type: .unknown, reason: "performV2 is not used")
    }
}

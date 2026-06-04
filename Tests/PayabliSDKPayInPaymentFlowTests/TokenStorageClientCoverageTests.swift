import Foundation
@testable import PayabliSDKCore
@testable import PayabliSDKPayInPaymentFlow
import XCTest

final class TokenStorageClientCoverageTests: XCTestCase {
    func testDiagnosticsLogFailureWithRelativeURLAndRedactedHeaders() async throws {
        let sink = CoverageDiagnosticSink()
        let transport = CoverageFailingTransport(error: PayabliGenericError(
            code: .networkError,
            reason: "Offline"
        ))
        let client = PayInPaymentFlowTokenStorageClient(
            transport: transport,
            accessTokenProvider: { "access-token-secret" },
            diagnostics: .enabled { sink.append($0) }
        )

        do {
            _ = try await client.addMethod(
                entryPoint: "entry",
                paymentMethod: .card(PayabliPayInPaymentFlowCardData(
                    cardNumber: "4111111111111111",
                    expiration: "02/28",
                    cardholderName: "Jane Doe",
                    cvv: "123",
                    billingZip: "33139"
                )),
                options: PayabliPayInPaymentFlowOptions(
                    createAnonymous: false,
                    temporary: true
                )
            )
            XCTFail("Expected transport error")
        } catch let error as PayabliGenericError {
            XCTAssertEqual(error.code, .networkError)
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        let entries = sink.entries()
        XCTAssertEqual(entries.map(\.phase), [.request, .failure])

        let failure = try XCTUnwrap(entries.last)
        XCTAssertEqual(failure.method, "POST")
        XCTAssertTrue(failure.url.hasPrefix("/api/TokenStorage/add?"))
        XCTAssertTrue(failure.url.contains("createAnonymous=false"))
        XCTAssertTrue(failure.url.contains("temporary=true"))
        XCTAssertEqual(failure.headers["Authorization"], "[REDACTED]")
        XCTAssertNil(failure.body)
        XCTAssertNotNil(failure.durationMilliseconds)
        XCTAssertFalse((failure.errorDescription ?? "").isEmpty)
    }

    func testDiagnosticsRedactsPANLikeValuesFromFailureMessages() async throws {
        let sink = CoverageDiagnosticSink()
        let transport = CoverageFailingTransport(error: PayabliGenericError(
            code: .networkError,
            reason: "Gateway echoed 4111 1111 1111 1111",
            detail: "Retry without card 4111111111111111."
        ))
        let client = PayInPaymentFlowTokenStorageClient(
            transport: transport,
            accessTokenProvider: { "access-token-secret" },
            diagnostics: .enabled { sink.append($0) }
        )

        do {
            _ = try await client.addMethod(
                entryPoint: "entry",
                paymentMethod: .card(PayabliPayInPaymentFlowCardData(
                    cardNumber: "4111111111111111",
                    expiration: "02/28",
                    cardholderName: "Jane Doe",
                    cvv: "123",
                    billingZip: "33139"
                ))
            )
            XCTFail("Expected transport error")
        } catch let error as PayabliGenericError {
            XCTAssertEqual(error.code, .networkError)
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        let failure = try XCTUnwrap(sink.entries().last)
        XCTAssertTrue(failure.errorDescription?.contains("[REDACTED]") == true)
        XCTAssertFalse(failure.errorDescription?.contains("4111111111111111") == true)
        XCTAssertFalse(failure.errorDescription?.contains("4111 1111 1111 1111") == true)
    }

    func testDiagnosticsRedactsArrayResponsesAndNonJSONBodies() async throws {
        let arraySink = CoverageDiagnosticSink()
        let arrayTransport = CoverageMockTransport(responseBody: """
        [
          {
            "cardNumber": "4111111111111111",
            "billingEmail": "jane@example.com",
            "resultText": "Visible"
          }
        ]
        """)
        let arrayClient = PayInPaymentFlowTokenStorageClient(
            transport: arrayTransport,
            accessTokenProvider: { "access-token" },
            diagnostics: .enabled { arraySink.append($0) }
        )

        do {
            _ = try await arrayClient.addMethod(
                entryPoint: "entry",
                paymentMethod: .card(PayabliPayInPaymentFlowCardData(
                    cardNumber: "4111111111111111",
                    expiration: "02/28",
                    cardholderName: "Jane Doe",
                    cvv: "123",
                    billingZip: "33139"
                ))
            )
            XCTFail("Expected decoding error")
        } catch let error as PayabliGenericError {
            XCTAssertEqual(error.code, .decodingError)
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        let arrayResponseBody = try XCTUnwrap(arraySink.entries().last?.body)
        XCTAssertTrue(arrayResponseBody.contains("\"resultText\":\"Visible\""))
        XCTAssertFalse(arrayResponseBody.contains("4111111111111111"))
        XCTAssertFalse(arrayResponseBody.contains("jane@example.com"))

        let nonJSONSink = CoverageDiagnosticSink()
        let nonJSONTransport = CoverageMockTransport(responseBody: "gateway text response")
        let nonJSONClient = PayInPaymentFlowTokenStorageClient(
            transport: nonJSONTransport,
            accessTokenProvider: { "access-token" },
            diagnostics: .enabled { nonJSONSink.append($0) }
        )

        do {
            _ = try await nonJSONClient.addMethod(
                entryPoint: "entry",
                paymentMethod: .card(PayabliPayInPaymentFlowCardData(
                    cardNumber: "4111111111111111",
                    expiration: "02/28",
                    cardholderName: "Jane Doe",
                    cvv: "123",
                    billingZip: "33139"
                ))
            )
            XCTFail("Expected decoding error")
        } catch let error as PayabliGenericError {
            XCTAssertEqual(error.code, .decodingError)
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        XCTAssertEqual(
            nonJSONSink.entries().last?.body,
            "[REDACTED NON-JSON BODY; 21 bytes]"
        )
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
            transport: transport,
            accessTokenProvider: { "access-token" }
        )

        let result = try await client.addMethod(
            entryPoint: "entry",
            paymentMethod: .card(PayabliPayInPaymentFlowCardData(
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
            transport: transport,
            accessTokenProvider: { "access-token" }
        )

        do {
            _ = try await client.addMethod(
                entryPoint: "entry",
                paymentMethod: .card(PayabliPayInPaymentFlowCardData(
                    cardNumber: "4111111111111111",
                    expiration: "02/28",
                    cardholderName: "Jane Doe",
                    cvv: "123",
                    billingZip: "33139"
                ))
            )
            XCTFail("Expected save failure")
        } catch let PayabliPayInPaymentFlowTokenStorageError.saveFailed(failure) {
            XCTAssertEqual(failure.responseText, "Gateway response")
            XCTAssertEqual(failure.resultCode, 2)
            XCTAssertEqual(failure.resultText, "Processor declined")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testInvalidEntryPointAndMissingAccessTokenDoNotReachTransport() async throws {
        let invalidEntryTransport = CoverageMockTransport(responseBody: "{}")
        let invalidEntryClient = PayInPaymentFlowTokenStorageClient(
            transport: invalidEntryTransport,
            accessTokenProvider: { "access-token" }
        )

        do {
            _ = try await invalidEntryClient.addMethod(
                entryPoint: "   ",
                paymentMethod: .card(PayabliPayInPaymentFlowCardData(
                    cardNumber: "4111111111111111",
                    expiration: "02/28",
                    cardholderName: "Jane Doe",
                    cvv: "123",
                    billingZip: "33139"
                ))
            )
            XCTFail("Expected invalid entrypoint error")
        } catch let PayabliPayInPaymentFlowTokenStorageError.invalidInput(message) {
            XCTAssertEqual(message, "Entrypoint is required.")
            let requests = await invalidEntryTransport.requests
            XCTAssertTrue(requests.isEmpty)
        } catch {
            XCTFail("Wrong error: \(error)")
        }

        let missingTokenTransport = CoverageMockTransport(responseBody: "{}")
        let missingTokenClient = PayInPaymentFlowTokenStorageClient(
            transport: missingTokenTransport,
            accessTokenProvider: { "  " }
        )

        do {
            _ = try await missingTokenClient.addMethod(
                entryPoint: "entry",
                paymentMethod: .card(PayabliPayInPaymentFlowCardData(
                    cardNumber: "4111111111111111",
                    expiration: "02/28",
                    cardholderName: "Jane Doe",
                    cvv: "123",
                    billingZip: "33139"
                ))
            )
            XCTFail("Expected missing token error")
        } catch PayabliPayInPaymentFlowTokenStorageError.missingAccessToken {
            let requests = await missingTokenTransport.requests
            XCTAssertTrue(requests.isEmpty)
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
        let viewModel = PayabliPayInPaymentFlowViewModel(
            component: PayabliPayInPaymentFlow(
                accessToken: "access-token-ach-hidden",
                entryPoint: "entry-ach-hidden",
                environment: .sandbox,
                transport: transport
            ),
            configuration: PayabliPayInPaymentFlowFormConfiguration(
                allowedMethods: [.ach],
                defaultMethod: .ach,
                hiddenValues: PayabliPayInPaymentFlowHiddenValues(achSecCode: nil)
            )
        )
        viewModel.achHolder = "Jane Business"
        viewModel.achRouting = "123456780"
        viewModel.achAccount = "1111111111111"

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
        throw PayabliGenericError(code: .unknown, reason: "performV2 is not used")
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
        throw PayabliGenericError(code: .unknown, reason: "performV2 is not used")
    }
}

private final class CoverageDiagnosticSink: @unchecked Sendable {
    private let lock = NSLock()
    private var captured: [PayabliPayInPaymentFlowDiagnosticEntry] = []

    func append(_ entry: PayabliPayInPaymentFlowDiagnosticEntry) {
        lock.lock()
        defer { lock.unlock() }
        captured.append(entry)
    }

    func entries() -> [PayabliPayInPaymentFlowDiagnosticEntry] {
        lock.lock()
        defer { lock.unlock() }
        return captured
    }
}

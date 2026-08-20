@testable import PayabliSDKCore
@testable import PayabliSDKPayInPaymentFlow
import XCTest

final class PayInPaymentFlowClientTests: XCTestCase {
    func testCaptureSerializesCardTransactionWithBearerAuthorization() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.approvedResponse)
        let client = PayInPaymentFlowClient(
            transport: transport,
            accessTokenProvider: { "access-token-1" }
        )

        let result = try await client.capture(
            entryPoint: "f743aed24a",
            request: cardRequest(
                achValidation: true,
                forceCustomerCreation: false,
                idempotencyKey: "idem-1"
            )
        )

        XCTAssertEqual(result.code, "A0000")
        XCTAssertEqual(result.transaction?.paymentTransId, "3040-transaction")
        XCTAssertEqual(result.transaction?.responseData?.authCode, "AUTH123")

        let request = try await firstRequest(from: transport)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/api/v2/MoneyIn/getpaid")
        XCTAssertEqual(request.headers["Authorization"], "Bearer access-token-1")
        XCTAssertNil(request.headers["requestToken"])
        XCTAssertEqual(request.headers["idempotencyKey"], "idem-1")
        XCTAssertEqual(request.query.map(\.name), ["achValidation", "forceCustomerCreation"])
        XCTAssertEqual(request.query.map(\.value), ["true", "false"])

        let body = try parseBody(request)
        XCTAssertEqual(body["entryPoint"] as? String, "f743aed24a")
        XCTAssertEqual(body["ipaddress"] as? String, "255.255.255.255")
        XCTAssertEqual(body["orderDescription"] as? String, "SDK test transaction")
        XCTAssertEqual(body["orderId"] as? String, "order-123")
        XCTAssertEqual(body["source"] as? String, "ios-sdk")

        let details = try XCTUnwrap(body["paymentDetails"] as? [String: Any])
        XCTAssertEqual(details["totalAmount"] as? Double, 100)
        XCTAssertEqual(details["serviceFee"] as? Double, 5)
        XCTAssertEqual(details["currency"] as? String, "USD")

        let customer = try XCTUnwrap(body["customerData"] as? [String: Any])
        XCTAssertEqual(customer["customerId"] as? Int, 4440)

        let paymentMethod = try XCTUnwrap(body["paymentMethod"] as? [String: Any])
        XCTAssertEqual(paymentMethod["method"] as? String, "card")
        XCTAssertEqual(paymentMethod["cardnumber"] as? String, "4111111111111111")
        XCTAssertEqual(paymentMethod["cardexp"] as? String, "02/27")
        XCTAssertEqual(paymentMethod["cardHolder"] as? String, "John Cassian")
        XCTAssertEqual(paymentMethod["cardcvv"] as? String, "999")
        XCTAssertEqual(paymentMethod["cardzip"] as? String, "12345")
        XCTAssertEqual(paymentMethod["initiator"] as? String, "payor")
        XCTAssertEqual(paymentMethod["saveIfSuccess"] as? Bool, true)
    }

    func testAuthorizeUsesAuthorizePathAndOmitsACHValidationQuery() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.authorizedResponse)
        let client = PayInPaymentFlowClient(
            transport: transport,
            accessTokenProvider: { "access-token-2" }
        )

        let result = try await client.authorize(
            entryPoint: "f743aed24a",
            request: cardRequest(achValidation: true)
        )

        XCTAssertEqual(result.code, "A0002")
        let request = try await firstRequest(from: transport)
        XCTAssertEqual(request.path, "/api/v2/MoneyIn/authorize")
        XCTAssertTrue(request.query.isEmpty)
        XCTAssertEqual(request.headers["Authorization"], "Bearer access-token-2")
        XCTAssertNil(request.headers["requestToken"])
    }

    func testPaymentDetailsCurrencyAmountsSerializeWithTwoDecimals() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.approvedResponse)
        let client = PayInPaymentFlowClient(
            transport: transport,
            accessTokenProvider: { "access-token" }
        )

        _ = try await client.capture(
            entryPoint: "entry",
            request: cardRequest(
                totalAmount: 1,
                serviceFee: 0.1 + 0.000_000_000_001
            )
        )

        let request = try await firstRequest(from: transport)
        let body = try XCTUnwrap(request.body)
        let bodyText = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(bodyText.contains(#""totalAmount":1.00"#), bodyText)
        XCTAssertTrue(bodyText.contains(#""serviceFee":0.10"#), bodyText)

        let parsedBody = try parseBody(request)
        let details = try XCTUnwrap(parsedBody["paymentDetails"] as? [String: Any])
        XCTAssertEqual(details["totalAmount"] as? Double, 1)
        XCTAssertEqual(details["serviceFee"] as? Double, 0.1)
    }

    func testAuthorizeRejectsACHBeforeTransport() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.approvedResponse)
        let client = PayInPaymentFlowClient(
            transport: transport,
            accessTokenProvider: { "access-token" }
        )

        do {
            _ = try await client.authorize(
                entryPoint: "entry",
                request: PayabliPayInPaymentFlowRequest(
                    paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 10),
                    paymentMethod: .ach(PayabliPayInPaymentFlowACHMethod(data: PayabliPayInPaymentFlowACHData(
                        accountNumber: "1111111111111",
                        accountType: .checking,
                        holderName: "John Doe",
                        routingNumber: "123456780"
                    )))
                )
            )
            XCTFail("Expected invalid input")
        } catch let PayabliPayInPaymentFlowError.invalidInput(message) {
            XCTAssertEqual(message, "Only card data can be authorized.")
            let requests = await transport.requests
            XCTAssertTrue(requests.isEmpty)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testAuthorizeRejectsStoredCardBeforeTransport() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.approvedResponse)
        let client = PayInPaymentFlowClient(
            transport: transport,
            accessTokenProvider: { "access-token" }
        )

        do {
            _ = try await client.authorize(
                entryPoint: "entry",
                request: PayabliPayInPaymentFlowRequest(
                    paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 10),
                    paymentMethod: .stored(PayabliPayInPaymentFlowStoredMethod(
                        method: .card,
                        storedMethodId: "stored-card-1"
                    ))
                )
            )
            XCTFail("Expected invalid input")
        } catch let PayabliPayInPaymentFlowError.invalidInput(message) {
            XCTAssertEqual(message, "Only card data can be authorized.")
            let requests = await transport.requests
            XCTAssertTrue(requests.isEmpty)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testCaptureAuthorizedSerializesPathAndPaymentDetailsOnly() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.approvedResponse)
        let client = PayInPaymentFlowClient(
            transport: transport,
            accessTokenProvider: { "access-token-3" }
        )

        _ = try await client.captureAuthorized(PayabliPayInPaymentFlowAuthorizedRequest(
            transId: "10-7d9cd67d-2d5d-4cd7-a1b7-72b8b201ec13",
            paymentDetails: PayabliPayInPaymentFlowPaymentDetails(
                totalAmount: 105,
                serviceFee: 5
            )
        ))

        let request = try await firstRequest(from: transport)
        XCTAssertEqual(request.path, "/api/v2/MoneyIn/capture/10-7d9cd67d-2d5d-4cd7-a1b7-72b8b201ec13")
        XCTAssertEqual(request.headers["Authorization"], "Bearer access-token-3")
        XCTAssertNil(request.headers["requestToken"])
        XCTAssertTrue(request.query.isEmpty)

        let body = try parseBody(request)
        XCTAssertNil(body["entryPoint"])
        XCTAssertNil(body["paymentMethod"])
        let details = try XCTUnwrap(body["paymentDetails"] as? [String: Any])
        XCTAssertEqual(details["totalAmount"] as? Double, 105)
        XCTAssertEqual(details["serviceFee"] as? Double, 5)
    }

    func testCaptureAuthorizedEscapesPathSeparatorsInTransactionId() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.approvedResponse)
        let client = PayInPaymentFlowClient(
            transport: transport,
            accessTokenProvider: { "access-token-4" }
        )

        _ = try await client.captureAuthorized(PayabliPayInPaymentFlowAuthorizedRequest(
            transId: "auth/id 1",
            paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 50)
        ))

        let request = try await firstRequest(from: transport)
        XCTAssertEqual(request.path, "/api/v2/MoneyIn/capture/auth%2Fid%201")
    }

    func testDeclineEnvelopeThrowsTransactionFailureInsteadOfGenericHTTPError() async throws {
        let transport = MockPaymentCaptureTransport(
            statusCode: 402,
            responseBody: """
            {
              "code": "D0200",
              "reason": "Insufficient Funds",
              "explanation": "The card issuer declined the transaction.",
              "action": "Ask for a different payment method.",
              "data": null,
              "token": null
            }
            """
        )
        let client = PayInPaymentFlowClient(
            transport: transport,
            accessTokenProvider: { "access-token" }
        )

        do {
            _ = try await client.capture(entryPoint: "entry", request: cardRequest())
            XCTFail("Expected transaction failure")
        } catch let PayabliPayInPaymentFlowError.transactionFailed(failure) {
            XCTAssertEqual(failure.code, "D0200")
            XCTAssertEqual(failure.httpStatusCode, 402)
            XCTAssertEqual(failure.reasonText, "The card issuer declined the transaction.")
            XCTAssertEqual(failure.detailText, "Ask for a different payment method.")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testLegacyFailureEnvelopeSurfacesResponseDataMessage() async throws {
        let transport = MockPaymentCaptureTransport(
            statusCode: 200,
            responseBody: """
            {
              "isSuccess": false,
              "responseText": "Unable to process payment",
              "responseCode": "400",
              "responseData": {
                "resultCode": "4001",
                "resultText": "Payment configuration rejected",
                "explanation": "The configured payment settings could not process this payment.",
                "todoAction": "Verify the payment capture configuration."
              }
            }
            """
        )
        let client = PayInPaymentFlowClient(
            transport: transport,
            accessTokenProvider: { "access-token" }
        )

        do {
            _ = try await client.capture(entryPoint: "entry", request: cardRequest())
            XCTFail("Expected transaction failure")
        } catch let PayabliPayInPaymentFlowError.transactionFailed(failure) {
            XCTAssertEqual(failure.code, "4001")
            XCTAssertEqual(failure.status, 400)
            XCTAssertEqual(
                failure.reasonText,
                "The configured payment settings could not process this payment."
            )
            XCTAssertEqual(failure.detailText, "Verify the payment capture configuration.")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testMissingAccessTokenDoesNotReachTransport() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.approvedResponse)
        let client = PayInPaymentFlowClient(
            transport: transport,
            accessTokenProvider: { "   " }
        )

        do {
            _ = try await client.capture(entryPoint: "entry", request: cardRequest())
            XCTFail("Expected missing token")
        } catch PayabliPayInPaymentFlowError.missingAccessToken {
            let requests = await transport.requests
            XCTAssertTrue(requests.isEmpty)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    /// The verification answer is the field that says why a card was refused, and
    /// the value a cardholder typed is next to it under a name one character apart.
    func testDiagnosticsShowsTheVerificationAnswerAndStillHidesTheSubmittedCVV() async throws {
        let declined = """
        {
          "isSuccess": false,
          "responseText": "Declined",
          "responseData": {
            "resultCode": 2,
            "resultText": "AVS or CVV failed",
            "cvvresponse": "N",
            "CVVResponse_Text": "no match",
            "avsresponse": "Z",
            "cvv": "123",
            "cardcvv": "456"
          }
        }
        """
        let expectation = expectation(description: "diagnostic response emitted")
        let transport = MockPaymentCaptureTransport(responseBody: declined)
        let responseEntry = LockedDiagnosticEntry()
        let diagnostics = PayabliPayInPaymentFlowDiagnostics.enabled { entry in
            if entry.phase == .response {
                responseEntry.set(entry)
                expectation.fulfill()
            }
        }
        let client = PayInPaymentFlowClient(
            transport: transport,
            accessTokenProvider: { "secret-token" },
            diagnostics: diagnostics
        )

        _ = try? await client.capture(entryPoint: "entry", request: cardRequest())

        await fulfillment(of: [expectation], timeout: 1)
        let body = try XCTUnwrap(try XCTUnwrap(responseEntry.value).body)

        // Allowed: the answer, whatever case and punctuation the service spells it in.
        XCTAssertTrue(body.contains(#""cvvresponse":"N""#), body)
        XCTAssertTrue(body.contains("no match"), body)
        XCTAssertTrue(body.contains(#""avsresponse":"Z""#), body)

        // Redacted: what was submitted, matched by the rules the allowlist runs before.
        XCTAssertTrue(body.contains(#""cvv":"[REDACTED]""#), body)
        XCTAssertTrue(body.contains(#""cardcvv":"[REDACTED]""#), body)
        XCTAssertFalse(body.contains("123"), body)
        XCTAssertFalse(body.contains("456"), body)
    }

    func testDiagnosticsRedactsBearerAndSensitivePaymentFields() async throws {
        let expectation = expectation(description: "diagnostic request emitted")
        let transport = MockPaymentCaptureTransport(responseBody: Self.approvedResponse)
        let requestEntry = LockedDiagnosticEntry()
        let diagnostics = PayabliPayInPaymentFlowDiagnostics.enabled { entry in
            if entry.phase == .request {
                requestEntry.set(entry)
                expectation.fulfill()
            }
        }
        let client = PayInPaymentFlowClient(
            transport: transport,
            accessTokenProvider: { "secret-token" },
            baseURL: URL(string: "https://api-sandbox.payabli.com"),
            diagnostics: diagnostics
        )

        _ = try await client.capture(entryPoint: "entry", request: cardRequest())

        await fulfillment(of: [expectation], timeout: 1)
        let entry = try XCTUnwrap(requestEntry.value)
        XCTAssertEqual(entry.headers["Authorization"], "[REDACTED]")
        XCTAssertTrue(entry.body?.contains(#""cardnumber":"[REDACTED]""#) == true)
        XCTAssertTrue(entry.body?.contains(#""cardcvv":"[REDACTED]""#) == true)
        XCTAssertTrue(entry.body?.contains(#""totalAmount":100.00"#) == true)
        XCTAssertTrue(entry.body?.contains(#""serviceFee":5.00"#) == true)
        XCTAssertFalse(entry.body?.contains("4111111111111111") == true)
        XCTAssertFalse(entry.body?.contains("secret-token") == true)
    }

    private func cardRequest(
        totalAmount: Double = 100,
        serviceFee: Double? = 5,
        achValidation: Bool? = nil,
        forceCustomerCreation: Bool? = nil,
        idempotencyKey: String? = nil
    ) -> PayabliPayInPaymentFlowRequest {
        PayabliPayInPaymentFlowRequest(
            paymentDetails: PayabliPayInPaymentFlowPaymentDetails(
                totalAmount: totalAmount,
                serviceFee: serviceFee,
                currency: "USD"
            ),
            paymentMethod: .card(PayabliPayInPaymentFlowCardMethod(
                data: PayabliPayInPaymentFlowCardData(
                    cardNumber: "4111 1111 1111 1111",
                    expiration: "02/27",
                    cardholderName: "John Cassian",
                    cvv: "999",
                    billingZip: "12345"
                ),
                saveIfSuccess: true
            )),
            customerData: PayabliPayInPaymentFlowCustomerData(customerId: 4440),
            ipAddress: "255.255.255.255",
            orderDescription: "SDK test transaction",
            orderId: "order-123",
            source: "ios-sdk",
            idempotencyKey: idempotencyKey,
            achValidation: achValidation,
            forceCustomerCreation: forceCustomerCreation
        )
    }

    private static let approvedResponse = """
    {
      "code": "A0000",
      "reason": "Approved",
      "explanation": "Approved by card network or card issuer.",
      "action": "No action required.",
      "data": {
        "paymentTransId": "3040-transaction",
        "gatewayTransId": "gateway-transaction",
        "orderId": "order-123",
        "method": "card",
        "transStatus": 1,
        "paypointId": 3040,
        "totalAmount": 100,
        "netAmount": 95,
        "feeAmount": 5,
        "settlementStatus": 0,
        "operation": "Sale",
        "responseData": {
          "resultCode": "A0000",
          "resultCodeText": "Approved",
          "responsetext": "CAPTURED",
          "authcode": "AUTH123",
          "transactionid": "processor-transaction",
          "response_code": "100",
          "response_code_text": "Operation successful"
        },
        "source": "api",
        "isValidatedACH": false,
        "transactionTime": "2025-12-01T09:50:03.559",
        "achSecCode": "",
        "achHolderType": "personal",
        "ipAddress": "255.255.255.255",
        "walletType": null
      },
      "token": null
    }
    """

    private static let authorizedResponse = """
    {
      "code": "A0002",
      "reason": "Authorized",
      "explanation": "Transaction authorized",
      "action": "No action required.",
      "data": {
        "paymentTransId": "3040-auth",
        "method": "card",
        "transStatus": 11,
        "operation": "Auth",
        "responseData": {
          "resultCode": "A0002",
          "resultCodeText": "Authorized",
          "responsetext": "AUTHORIZED",
          "authcode": "AUTH999"
        }
      },
      "token": null
    }
    """
}

private actor MockPaymentCaptureTransport: PayabliTransport {
    private(set) var requests: [PayabliRequest] = []
    private let statusCode: Int
    private let responseBody: String

    init(statusCode: Int = 201, responseBody: String) {
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
        decoding _: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        requests.append(request)
        return try JSONDecoder().decode(PayabliV2Envelope<T>.self, from: Data(responseBody.utf8))
    }
}

private final class LockedDiagnosticEntry: @unchecked Sendable {
    private let lock = NSLock()
    private var entry: PayabliPayInPaymentFlowDiagnosticEntry?

    var value: PayabliPayInPaymentFlowDiagnosticEntry? {
        lock.lock()
        defer { lock.unlock() }
        return entry
    }

    func set(_ entry: PayabliPayInPaymentFlowDiagnosticEntry) {
        lock.lock()
        defer { lock.unlock() }
        self.entry = entry
    }
}

private func firstRequest(from transport: MockPaymentCaptureTransport) async throws -> PayabliRequest {
    let requests = await transport.requests
    return try XCTUnwrap(requests.first)
}

private func parseBody(_ request: PayabliRequest) throws -> [String: Any] {
    let body = try XCTUnwrap(request.body)
    let object = try JSONSerialization.jsonObject(with: body)
    return try XCTUnwrap(object as? [String: Any])
}

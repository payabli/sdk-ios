@testable import PayabliSDKCore
@testable import PayabliSDKPayIn
import XCTest

final class PayInPaymentFlowClientTests: XCTestCase {
    func testCaptureSerializesCardTransactionWithBearerAuthorization() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.approvedResponse)
        let client = PayInPaymentFlowClient(
            transport: transport
        )

        let result = try await client.capture(
            entryPoint: "f743aed24a",
            request: cardRequest(
                achValidation: true,
                forceCustomerCreation: false
            ),
            idempotencyKey: "idem-1"
        )

        XCTAssertEqual(result.code, "A0000")
        XCTAssertEqual(result.transaction?.paymentTransId, "3040-transaction")
        XCTAssertEqual(result.transaction?.responseData?.authCode, "AUTH123")

        let request = try await firstRequest(from: transport)
        XCTAssertEqual(request.method, .post)
        XCTAssertEqual(request.path, "/api/v2/MoneyIn/getpaid")
        XCTAssertNil(request.headers["Authorization"], "the client contributes no credential")
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
            transport: transport
        )

        let result = try await client.authorize(
            entryPoint: "f743aed24a",
            request: cardRequest(achValidation: true)
        )

        XCTAssertEqual(result.code, "A0002")
        let request = try await firstRequest(from: transport)
        XCTAssertEqual(request.path, "/api/v2/MoneyIn/authorize")
        XCTAssertTrue(request.query.isEmpty)
        XCTAssertNil(request.headers["Authorization"], "the client contributes no credential")
        XCTAssertNil(request.headers["requestToken"])
    }

    func testPaymentDetailsCurrencyAmountsSerializeWithTwoDecimals() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.approvedResponse)
        let client = PayInPaymentFlowClient(
            transport: transport
        )

        _ = try await client.capture(
            entryPoint: "entry",
            request: cardRequest(
                totalAmount: 1,
                serviceFee: 0.1 + 0.000_000_000_001,
                surchargeFee: 0.3 + 0.000_000_000_001
            )
        )

        let request = try await firstRequest(from: transport)
        let body = try XCTUnwrap(request.body)
        let bodyText = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertTrue(bodyText.contains(#""totalAmount":1.00"#), bodyText)
        XCTAssertTrue(bodyText.contains(#""serviceFee":0.10"#), bodyText)
        XCTAssertTrue(bodyText.contains(#""surchargeFee":0.30"#), bodyText)

        let parsedBody = try parseBody(request)
        let details = try XCTUnwrap(parsedBody["paymentDetails"] as? [String: Any])
        XCTAssertEqual(details["totalAmount"] as? Double, 1)
        XCTAssertEqual(details["serviceFee"] as? Double, 0.1)
        XCTAssertEqual(details["surchargeFee"] as? Double, 0.3)
    }

    func testPaymentDetailsWithoutASurchargeSendNone() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.approvedResponse)
        let client = PayInPaymentFlowClient(
            transport: transport
        )

        _ = try await client.capture(
            entryPoint: "entry",
            request: cardRequest(surchargeFee: nil)
        )

        let request = try await firstRequest(from: transport)
        let body = try XCTUnwrap(request.body)
        let bodyText = try XCTUnwrap(String(data: body, encoding: .utf8))
        XCTAssertFalse(bodyText.contains("surchargeFee"), bodyText)

        let parsedBody = try parseBody(request)
        let details = try XCTUnwrap(parsedBody["paymentDetails"] as? [String: Any])
        XCTAssertNil(details["surchargeFee"])
    }

    func testCaptureAuthorizedSerializesPathAndPaymentDetailsOnly() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.approvedResponse)
        let client = PayInPaymentFlowClient(
            transport: transport
        )

        _ = try await client.captureAuthorized(PayabliPayInAuthorizedRequest(
            transId: "10-7d9cd67d-2d5d-4cd7-a1b7-72b8b201ec13",
            paymentDetails: PayabliPayInPaymentDetails(
                totalAmount: 105,
                serviceFee: 5
            )
        ))

        let request = try await firstRequest(from: transport)
        XCTAssertEqual(request.path, "/api/v2/MoneyIn/capture/10-7d9cd67d-2d5d-4cd7-a1b7-72b8b201ec13")
        XCTAssertNil(request.headers["Authorization"], "the client contributes no credential")
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
            transport: transport
        )

        _ = try await client.captureAuthorized(PayabliPayInAuthorizedRequest(
            transId: "auth/id 1",
            paymentDetails: PayabliPayInPaymentDetails(totalAmount: 50)
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
            transport: transport
        )

        do {
            _ = try await client.capture(entryPoint: "entry", request: cardRequest())
            XCTFail("Expected transaction failure")
        } catch let PayabliPayInError.transactionFailed(failure) {
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
            transport: transport
        )

        do {
            _ = try await client.capture(entryPoint: "entry", request: cardRequest())
            XCTFail("Expected transaction failure")
        } catch let PayabliPayInError.transactionFailed(failure) {
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

    /// A provider that throws reaches the caller as this SDK's own error, not the host's error verbatim.
    @MainActor
    func testAProviderFailureSurfacesAsTheSDKsOwnError() async throws {
        let sentinel = "SENTINEL-BACKEND-https://tokens.internal.example/mint?client=acme"
        let config = try PayabliConfig(
            entryPoint: "entry",
            environment: .sandbox,

            tokenProvider: {
                throw NSError(
                    domain: sentinel,
                    code: 1,
                    userInfo: [NSLocalizedDescriptionKey: sentinel]
                )
            }
        )
        let component = PayabliPayIn(session: PayabliSession(config: config, telemetryTransport: DiscardingTelemetryTransport()))

        do {
            _ = try await component.capture(cardRequest())
            XCTFail("Expected the provider failure to surface")
        } catch let error as PayabliGenericError {
            // The holder owns the provider now, so a host failure arrives as this SDK's own
            // `.tokenProviderFailed` with the cause redacted, rather than as the host's error verbatim.
            XCTAssertEqual(error.type, .tokenProviderFailed)
            XCTAssertFalse(error.reason.contains("SENTINEL-BACKEND"), error.reason)
        }
    }

    /// A blank token is refused where it is installed, which is the session's holder.
    ///
    /// Driven through the facade's own transport, because injecting a double never reads a
    /// credential. Nothing reaches the network: the read runs before the request is built, pinned in
    /// Core by `testAFailingTokenReadStopsTheRequestBeforeItIsSent`.
    @MainActor
    func testMissingAccessTokenIsRefusedBeforeAnythingIsSent() async throws {
        let component = flowOnSession(token: "   ")

        do {
            _ = try await component.capture(cardRequest())
            XCTFail("Expected missing token")
        } catch let error as PayabliGenericError {
            XCTAssertEqual(error.type, .tokenProviderFailed)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    /// The credential is attached below this client, so the request it hands the transport carries none.
    func testACaptureRequestCarriesItsAmountsAndNoCredential() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.approvedResponse)
        let client = PayInPaymentFlowClient(transport: transport)

        _ = try await client.capture(entryPoint: "entry", request: cardRequest())

        let request = try await firstRequest(from: transport)
        let body = try XCTUnwrap(String(bytes: XCTUnwrap(request.body), encoding: .utf8))
        XCTAssertFalse(request.headers.keys.contains { $0.lowercased() == "authorization" })
        XCTAssertTrue(body.contains(#""totalAmount":100.00"#))
        XCTAssertTrue(body.contains(#""serviceFee":5.00"#))
    }

    /// The card's own bytes: one object, the payment method as its last member, and the card number
    /// and security code as digits with the entry's separators dropped.
    func testTheCardMethodIsWrittenAsBytesAsTheBodyLastMember() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.approvedResponse)
        let client = PayInPaymentFlowClient(transport: transport)

        _ = try await client.capture(entryPoint: "entry", request: cardRequest())

        let request = try await firstRequest(from: transport)
        let bodyText = try XCTUnwrap(String(data: XCTUnwrap(request.body), encoding: .utf8))
        XCTAssertEqual(
            bodyText,
            #"{"customerData":{"customerId":4440},"entryPoint":"entry","ipaddress":"255.255.255.255","orderDescription":"SDK test transaction","orderId":"order-123","#
                + #""paymentDetails":{"currency":"USD","serviceFee":5.00,"totalAmount":100.00},"#
                + #""source":"ios-sdk","paymentMethod":{"cardHolder":"John Cassian","cardcvv":"999","cardexp":"02\/27","#
                + #""cardnumber":"4111111111111111","cardzip":"12345","initiator":"payor","method":"card","saveIfSuccess":true}}"#
        )
    }

    private func cardRequest(
        totalAmount: Double = 100,
        serviceFee: Double? = 5,
        surchargeFee: Double? = nil,
        achValidation: Bool? = nil,
        forceCustomerCreation: Bool? = nil,
        additionalData: [String: String]? = nil
    ) -> PayabliPayInRequest {
        PayabliPayInRequest(
            paymentMethod: .card(PayabliPayInPaymentMethod.Card(
                data: PayabliPayInCardData(
                    cardNumber: SensitiveDigits.ofString("4111 1111 1111 1111"),
                    expiry: "02/27",
                    holderName: "John Cassian",
                    securityCode: SensitiveDigits.ofString("999"),
                    postalCode: "12345"
                ),
                saveIfSuccess: true
            )),
            options: PayabliPayInRequestConfiguration(
                paymentDetails: PayabliPayInPaymentDetails(
                    totalAmount: totalAmount,
                    serviceFee: serviceFee,
                    surchargeFee: surchargeFee,
                    currency: "USD"
                ),
                customerData: PayabliPayInCustomerData(
                    additionalData: additionalData,
                    customerId: 4440
                ),
                ipAddress: "255.255.255.255",
                orderDescription: "SDK test transaction",
                orderId: "order-123",
                source: "ios-sdk",
                achValidation: achValidation,
                forceCustomerCreation: forceCustomerCreation
            )
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

actor MockPaymentCaptureTransport: PayabliTransport {
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

func firstRequest(from transport: MockPaymentCaptureTransport) async throws -> PayabliRequest {
    let requests = await transport.requests
    return try XCTUnwrap(requests.first)
}

private func parseBody(_ request: PayabliRequest) throws -> [String: Any] {
    let body = try XCTUnwrap(request.body)
    let object = try JSONSerialization.jsonObject(with: body)
    return try XCTUnwrap(object as? [String: Any])
}

/// Reserves the key the way the facade does, so these cases can exercise the client alone.
///
/// The client takes the key as a parameter rather than reading it off the request, and the parameter is
/// mandatory, which is the whole of the point: a money-moving call cannot be written that omits it.
/// Nothing reports the key. These
/// overloads apply the same rule the facade applies, so a case that supplies a key still asserts on
/// its own key.
private extension PayInPaymentFlowClient {
    func capture(
        entryPoint: String,
        request: PayabliPayInRequest
    ) async throws -> PayabliPayInResult {
        try await capture(
            entryPoint: entryPoint,
            request: request,
            idempotencyKey: "reserved-by-test"
        )
    }

    func authorize(
        entryPoint: String,
        request: PayabliPayInRequest
    ) async throws -> PayabliPayInResult {
        try await authorize(
            entryPoint: entryPoint,
            request: request,
            idempotencyKey: "reserved-by-test"
        )
    }

    func captureAuthorized(
        _ request: PayabliPayInAuthorizedRequest
    ) async throws -> PayabliPayInResult {
        try await captureAuthorized(
            request,
            idempotencyKey: "reserved-by-test"
        )
    }
}

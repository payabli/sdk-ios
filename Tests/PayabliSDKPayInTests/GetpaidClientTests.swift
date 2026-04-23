import XCTest
import PayabliSDKCore
@testable import PayabliSDKPayIn

final class GetpaidClientTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeClient(
        tokenProvider: PayabliTokenRefresh? = nil
    ) -> (GetpaidClient, PayabliAuth) {
        let session = StubURLProtocol.makeSession()
        let service = PayabliService(environment: .sandbox, session: session)
        let config = PayabliConfig(
            accessToken: "seed_token",
            tokenProvider: tokenProvider,
            entryPoint: "f743aed24a",
            environment: .sandbox
        )
        let auth = PayabliAuth(config: config)
        return (GetpaidClient(service: service, auth: auth), auth)
    }

    private func cardPayload() -> CardTokenizationPayload {
        CardTokenizationPayload(
            cardnumber: "4111111111111111",
            cardexp: "0227",
            cardcvv: "999",
            cardHolder: "John Cassian",
            cardzip: "12345"
        )
    }

    private func paymentRequest(
        saveIfSuccess: Bool = false,
        idempotencyKey: String? = nil,
        storedMethodId: String? = nil
    ) -> PayabliPaymentRequest {
        PayabliPaymentRequest(
            totalAmount: 100,
            serviceFee: 0,
            currency: "USD",
            saveIfSuccess: saveIfSuccess,
            idempotencyKey: idempotencyKey,
            storedMethodId: storedMethodId
        )
    }

    // MARK: - Approved

    func testApprovedCardTransaction() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/v2/MoneyIn/getpaid")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer seed_token")
            XCTAssertNotNil(request.value(forHTTPHeaderField: "idempotencyKey"))

            let json = """
            {
              "code":"A0000",
              "reason":"Approved",
              "explanation":"Transaction approved.",
              "action":"No action required.",
              "data":{
                "paymentTransId":"txn_abc123",
                "gatewayTransId":"gw_xyz789",
                "method":"card",
                "totalAmount":100.00,
                "operation":"sale",
                "paymentData":{
                  "maskedAccount":"****1111",
                  "accountType":"Visa",
                  "storedId":"saved-uuid",
                  "initiator":"payor",
                  "sequence":"first"
                },
                "responseData":{
                  "resultCode":"A0000",
                  "authcode":"AUTH123",
                  "transactionid":"proc_123456"
                }
              },
              "token":"chained_next"
            }
            """
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }

        let (client, _) = makeClient()
        let result = try await client.chargeCard(
            payload: cardPayload(),
            request: paymentRequest(saveIfSuccess: true),
            customerId: 4440,
            entryPoint: "f743aed24a"
        )
        XCTAssertEqual(result.paymentTransId, "txn_abc123")
        XCTAssertEqual(result.responseCode, "A0000")
        XCTAssertEqual(result.authCode, "AUTH123")
        XCTAssertEqual(result.maskedAccount, "****1111")
        XCTAssertEqual(result.methodReferenceId, "saved-uuid")
    }

    // MARK: - Declined (402)

    func testDeclinedTransactionSurfacesDeclineError() async throws {
        StubURLProtocol.handler = { request in
            let json = """
            {
              "code":"D0001",
              "reason":"Card Declined",
              "explanation":"The card was declined by the issuing bank.",
              "action":"Ask the cardholder to use a different payment method."
            }
            """
            return (HTTPURLResponse(url: request.url!, statusCode: 402, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }

        let (client, _) = makeClient()
        do {
            _ = try await client.chargeCard(
                payload: cardPayload(),
                request: paymentRequest(),
                customerId: 4440,
                entryPoint: "e"
            )
            XCTFail("expected decline")
        } catch PayabliPaymentError.decline(let err) {
            XCTAssertEqual(err.rawCode, "D0001")
            XCTAssertEqual(err.reason, "Card Declined")
            XCTAssertNotNil(err.action)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Validation (400)

    func testValidationErrorMappedFromRFC7807() async throws {
        StubURLProtocol.handler = { request in
            let json = """
            {
              "title":"Bad Request",
              "status":400,
              "detail":"One or more validation errors occurred.",
              "code":"E0001",
              "errors":{"paymentMethod.cardnumber":[{"message":"Card number is invalid.","suggestion":"Check the card number and try again."}]}
            }
            """
            return (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }

        let (client, _) = makeClient()
        do {
            _ = try await client.chargeCard(
                payload: cardPayload(),
                request: paymentRequest(),
                customerId: 4440,
                entryPoint: "e"
            )
            XCTFail("expected validation")
        } catch PayabliPaymentError.validation(let err) {
            XCTAssertEqual(err.status, 400)
            XCTAssertNotNil(err.errors?["paymentMethod.cardnumber"])
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    // MARK: - Idempotency

    func testHostSuppliedIdempotencyKeyForwarded() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "idempotencyKey"), "host-key-123")
            let json = """
            {"code":"A0000","data":{"paymentTransId":"t"}}
            """
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }

        let (client, _) = makeClient()
        _ = try await client.chargeCard(
            payload: cardPayload(),
            request: paymentRequest(idempotencyKey: "host-key-123"),
            customerId: 4440,
            entryPoint: "e"
        )
    }

    func testAutoGeneratedIdempotencyKeyIsUUID() async throws {
        StubURLProtocol.handler = { request in
            let key = request.value(forHTTPHeaderField: "idempotencyKey") ?? ""
            XCTAssertNotNil(UUID(uuidString: key))
            let json = """
            {"code":"A0000","data":{"paymentTransId":"t"}}
            """
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }

        let (client, _) = makeClient()
        _ = try await client.chargeCard(
            payload: cardPayload(),
            request: paymentRequest(),
            customerId: 4440,
            entryPoint: "e"
        )
    }

    // MARK: - Stored method

    func testStoredMethodChargeSendsStoredMethodId() async throws {
        StubURLProtocol.handler = { request in
            // Verify payload shape — canonicalRequest drains the body stream into httpBody.
            let raw = request.httpBody ?? Data()
            guard !raw.isEmpty else {
                XCTFail("Expected a non-empty request body")
                return (HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!, Data())
            }
            let body = try JSONSerialization.jsonObject(with: raw) as? [String: Any]
            let method = body?["paymentMethod"] as? [String: Any]
            XCTAssertEqual(method?["method"] as? String, "card")
            XCTAssertEqual(method?["storedMethodId"] as? String, "stored-uuid-4440")
            XCTAssertEqual(method?["initiator"] as? String, "merchant")
            XCTAssertEqual(method?["storedMethodUsageType"] as? String, "unscheduled")

            let json = """
            {"code":"A0000","data":{"paymentTransId":"t_stored"}}
            """
            return (HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }

        let (client, _) = makeClient()
        let request = PayabliPaymentRequest(
            totalAmount: 100,
            saveIfSuccess: false,
            storedMethodId: "stored-uuid-4440",
            storedMethodUsageType: .unscheduled
        )
        let result = try await client.chargeStoredMethod(
            methodType: .card,
            request: request,
            customerId: 4440,
            entryPoint: "e"
        )
        XCTAssertEqual(result.paymentTransId, "t_stored")
    }

    func testStoredMethodRejectsUnsupportedMethodType() async throws {
        let (client, _) = makeClient()
        do {
            _ = try await client.chargeStoredMethod(
                methodType: .applePay,
                request: PayabliPaymentRequest(totalAmount: 10, storedMethodId: "x"),
                customerId: 1,
                entryPoint: "e"
            )
            XCTFail("expected error")
        } catch let err as PayabliGenericError {
            XCTAssertEqual(err.code, .invalidConfiguration)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testStoredMethodRequiresStoredId() async throws {
        let (client, _) = makeClient()
        do {
            _ = try await client.chargeStoredMethod(
                methodType: .card,
                request: PayabliPaymentRequest(totalAmount: 10),
                customerId: 1,
                entryPoint: "e"
            )
            XCTFail("expected error")
        } catch let err as PayabliGenericError {
            XCTAssertEqual(err.code, .invalidConfiguration)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}

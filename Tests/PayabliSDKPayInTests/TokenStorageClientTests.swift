import XCTest
import PayabliSDKCore
@testable import PayabliSDKPayIn

final class TokenStorageClientTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func makeClient(
        tokenProvider: PayabliTokenRefresh? = nil
    ) -> (TokenStorageClient, PayabliService, PayabliAuth) {
        let session = StubURLProtocol.makeSession()
        let service = PayabliService(environment: .sandbox, session: session)
        let config = PayabliConfig(
            accessToken: "seed_token",
            tokenProvider: tokenProvider,
            entryPoint: "e",
            environment: .sandbox
        )
        let auth = PayabliAuth(config: config)
        return (TokenStorageClient(service: service, auth: auth), service, auth)
    }

    private func cardRequest() -> CardTokenizationRequest {
        CardTokenizationRequest(
            customerData: CustomerDataBlock(customerId: 1),
            entryPoint: "e",
            paymentMethod: CardTokenizationPayload(
                cardnumber: "4111111111111111",
                cardexp: "0530",
                cardcvv: "123",
                cardHolder: "Jane",
                cardzip: "90210"
            )
        )
    }

    // MARK: - Happy paths

    func testCardTokenizationEnvelopeResponse() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/api/TokenStorage/add")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer seed_token")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let body = Data("{\"isSuccess\":true,\"responseData\":\"tok_abc123\"}".utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let (client, _, _) = makeClient()
        let token = try await client.tokenizeCard(cardRequest())
        XCTAssertEqual(token, "tok_abc123")
    }

    func testCardTokenizationBareStringResponse() async throws {
        StubURLProtocol.handler = { request in
            let body = Data("\"tok_bare_xyz\"".utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let (client, _, _) = makeClient()
        let token = try await client.tokenizeCard(cardRequest())
        XCTAssertEqual(token, "tok_bare_xyz")
    }

    func testACHTokenizationAppendsValidationQuery() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.query, "achValidation=true")
            let body = Data("\"tok_ach_1\"".utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, body)
        }
        let (client, _, _) = makeClient()
        let token = try await client.tokenizeACH(ACHTokenizationRequest(
            customerData: CustomerDataBlock(customerId: 1),
            entryPoint: "e",
            paymentMethod: ACHTokenizationPayload(
                achAccount: "12345",
                achRouting: "021000021",
                achAccountType: .checking,
                achHolder: "Jane",
                achHolderType: .personal
            )
        ))
        XCTAssertEqual(token, "tok_ach_1")
    }

    // MARK: - Error paths

    func testValidationError() async throws {
        StubURLProtocol.handler = { request in
            let json = """
            {"title":"Bad Request","status":400,"code":"E0001","errors":{"paymentMethod.cardnumber":[{"message":"Invalid","suggestion":""}]}}
            """
            return (HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!, Data(json.utf8))
        }
        let (client, _, _) = makeClient()
        do {
            _ = try await client.tokenizeCard(cardRequest())
            XCTFail("expected error")
        } catch PayabliPaymentError.validation(let err) {
            XCTAssertEqual(err.status, 400)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }

    func testAuthErrorInvalidatesToken() async throws {
        StubURLProtocol.handler = { request in
            let headers = ["Content-Type": "application/json"]
            return (HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: headers)!, Data("{}".utf8))
        }
        let (client, _, _) = makeClient()
        do {
            _ = try await client.tokenizeCard(cardRequest())
            XCTFail("expected error")
        } catch let err as PayabliGenericError {
            XCTAssertEqual(err.code, .tokenExpired)
        } catch {
            XCTFail("wrong error: \(error)")
        }
    }
}

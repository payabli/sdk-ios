import XCTest
import PayabliSDKCore
import PayabliSDKTestUtils

private struct FakeData: Decodable, Sendable {
    let paymentTransId: String
}

final class PayabliServiceTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func service() -> PayabliService {
        PayabliService(environment: .sandbox, session: StubURLProtocol.makeSession())
    }

    // MARK: - V2 envelope decoding

    func testDecodesV2ApprovedEnvelope() async throws {
        StubURLProtocol.handler = { request in
            let json = """
            {
              "code": "A0000",
              "reason": "Approved",
              "data": {"paymentTransId": "txn_002"}
            }
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 201, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let request = PayabliRequest(method: .post, path: "/api/v2/MoneyIn/getpaid")
        let envelope = try await service().performV2(request, decoding: FakeData.self)
        XCTAssertTrue(envelope.isApproved)
        XCTAssertFalse(envelope.isDeclined)
        XCTAssertEqual(envelope.data?.paymentTransId, "txn_002")
    }

    // MARK: - Error mapping

    func testMaps400ToValidationError() async throws {
        StubURLProtocol.handler = { request in
            let json = """
            {
              "title":"Bad Request",
              "status":400,
              "detail":"One or more validation errors occurred.",
              "instance":"/api/v2/MoneyIn/getpaid",
              "code":"E0001",
              "errors":{"paymentMethod.cardnumber":[{"message":"Card number is invalid.","suggestion":"Check the card number"}]}
            }
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let request = PayabliRequest(method: .post, path: "/api/v2/MoneyIn/getpaid")
        do {
            _ = try await service().performV2(request, decoding: FakeData.self)
            XCTFail("Expected error")
        } catch PayabliPaymentError.validation(let err) {
            XCTAssertEqual(err.status, 400)
            XCTAssertNotNil(err.errors?["paymentMethod.cardnumber"])
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testMaps401ToTokenExpired() async throws {
        StubURLProtocol.handler = { request in
            let headers = ["Content-Type": "application/json"]
            let response = HTTPURLResponse(url: request.url!, statusCode: 401, httpVersion: "HTTP/1.1", headerFields: headers)!
            return (response, Data("{\"error\":\"unauthorized\"}".utf8))
        }

        let request = PayabliRequest(method: .get, path: "/test")
        do {
            _ = try await service().performV2(request, decoding: FakeData.self)
            XCTFail("Expected error")
        } catch let err as PayabliGenericError {
            XCTAssertEqual(err.code, .tokenExpired)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testMaps402ToDeclineError() async throws {
        StubURLProtocol.handler = { request in
            let json = """
            {
              "code":"D0001",
              "reason":"Card Declined",
              "explanation":"The card was declined by the issuing bank.",
              "action":"Ask the cardholder to use a different payment method."
            }
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 402, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let request = PayabliRequest(method: .post, path: "/api/v2/MoneyIn/getpaid")
        do {
            _ = try await service().performV2(request, decoding: FakeData.self)
            XCTFail("Expected error")
        } catch PayabliPaymentError.decline(let err) {
            XCTAssertEqual(err.rawCode, "D0001")
            XCTAssertEqual(err.reason, "Card Declined")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testMaps500ToServerError() async throws {
        StubURLProtocol.handler = { request in
            let json = """
            {"title":"Internal Server Error","status":500,"detail":"Boom","instance":"/x"}
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 500, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let request = PayabliRequest(method: .post, path: "/x")
        do {
            _ = try await service().performV2(request, decoding: FakeData.self)
            XCTFail("Expected error")
        } catch PayabliPaymentError.server(let err) {
            XCTAssertEqual(err.status, 500)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    // MARK: - Request building

    func testAppendsQueryItems() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.query, "achValidation=true")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        let request = PayabliRequest(
            method: .post,
            path: "/api/TokenStorage/add",
            query: [URLQueryItem(name: "achValidation", value: "true")]
        )
        _ = try await service().perform(request)
    }

    func testAttachesHeaders() async throws {
        StubURLProtocol.handler = { request in
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer abc123")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        let request = PayabliRequest(
            method: .post,
            path: "/test",
            headers: ["Authorization": "Bearer abc123", "Content-Type": "application/json"]
        )
        _ = try await service().perform(request)
    }
}

import PayabliSDKCore
import PayabliSDKTestUtils
import XCTest

private struct FakeData: Decodable, Sendable {
    let paymentTransId: String
}

final class PayabliServiceTests: XCTestCase {
    override func tearDown() {
        StubURLProtocol.handler = nil
        super.tearDown()
    }

    private func service() -> PayabliService {
        PayabliService(
            environment: .sandbox,
            readToken: { testToken },
            session: StubURLProtocol.makeSession()
        )
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
        } catch let PayabliPaymentError.validation(err) {
            XCTAssertEqual(err.status, 400)
            XCTAssertNotNil(err.errors?["paymentMethod.cardnumber"])
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    /// The body above is the object form. The platform's model validation sends a
    /// map of string arrays instead, and both bodies below were captured from api-qa.
    func testMaps400WithStringFieldErrorsToValidationError() async throws {
        StubURLProtocol.handler = { request in
            let json = """
            {"errors": {"Entry": ["The Entry field is required."]},
             "status": 400, "title": "One or more validation errors occurred.",
             "type": "https://tools.ietf.org/html/rfc9110#section-15.5.1"}
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let request = PayabliRequest(method: .post, path: "/api/v2/MoneyIn/getpaid")
        do {
            _ = try await service().performV2(request, decoding: FakeData.self)
            XCTFail("Expected error")
        } catch let PayabliPaymentError.validation(err) {
            XCTAssertEqual(err.title, "One or more validation errors occurred.")
            XCTAssertEqual(err.type, "https://tools.ietf.org/html/rfc9110#section-15.5.1")
            XCTAssertEqual(err.errors?["Entry"]?.first?.message, "The Entry field is required.")
            XCTAssertNil(err.errors?["Entry"]?.first?.suggestion)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    /// The v2 MoneyIn 400 verbatim from api-qa, which sends the object form and a
    /// null `token`. Both endpoint families are live, so neither shape replaces the
    /// other: this one and the string form above come from the same SDK's calls.
    func testMaps400FromMoneyInDecodesObjectFormAndNullToken() async throws {
        let serverMessage = "The token does not have access to entity in scope "
            + "or the token is not allowed to execute requested action"
        StubURLProtocol.handler = { request in
            let json = """
            {"code":"E9001","detail":"Invalid Authorization Token",
             "errors":{"entryPoint":[{"message":"\(serverMessage)",
                                      "suggestion":"Use an authorized API token for the request."}]},
             "instance":"/api/v2/MoneyIn/getpaid","status":400,"title":"Bad Request",
             "token":null,
             "type":"https://docs.payabli.com/developers/references/pay-in-unified-response-codes"}
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let request = PayabliRequest(method: .post, path: "/api/v2/MoneyIn/getpaid")
        do {
            _ = try await service().performV2(request, decoding: FakeData.self)
            XCTFail("Expected error")
        } catch let PayabliPaymentError.validation(err) {
            XCTAssertEqual(err.rawCode, "E9001")
            XCTAssertEqual(err.detail, "Invalid Authorization Token")
            XCTAssertNil(err.token)
            XCTAssertEqual(err.errors?["entryPoint"]?.first?.message, serverMessage)
            XCTAssertEqual(
                err.errors?["entryPoint"]?.first?.suggestion,
                "Use an authorized API token for the request."
            )
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testMaps400WithMissingPropertyErrorsToValidationError() async throws {
        StubURLProtocol.handler = { request in
            let json = """
            {"errors": {"$": ["JSON deserialization for type 'AttestRequest' was missing required properties including: 'platform'."],
                        "request": ["The request field is required."]},
             "status": 400, "title": "One or more validation errors occurred.",
             "type": "https://tools.ietf.org/html/rfc9110#section-15.5.1"}
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let request = PayabliRequest(method: .post, path: "/api/v2/MoneyIn/getpaid")
        do {
            _ = try await service().performV2(request, decoding: FakeData.self)
            XCTFail("Expected error")
        } catch let PayabliPaymentError.validation(err) {
            XCTAssertEqual(
                err.errors?["$"]?.first?.message,
                "JSON deserialization for type 'AttestRequest' was missing required properties including: 'platform'."
            )
            XCTAssertEqual(err.errors?["request"]?.first?.message, "The request field is required.")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    /// The status fixes the classification and the body only decides how many fields
    /// get filled, so an `errors` map in a shape neither form covers costs the field
    /// list and nothing else.
    func testMaps400WithUnreadableFieldErrorsKeepsTheClassification() async throws {
        StubURLProtocol.handler = { request in
            let json = """
            {"errors": {"Entry": [42]},
             "status": 400, "title": "One or more validation errors occurred."}
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let request = PayabliRequest(method: .post, path: "/api/v2/MoneyIn/getpaid")
        do {
            _ = try await service().performV2(request, decoding: FakeData.self)
            XCTFail("Expected error")
        } catch let PayabliPaymentError.validation(err) {
            XCTAssertEqual(err.title, "One or more validation errors occurred.")
            XCTAssertTrue(err.errors?.isEmpty ?? true)
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    /// A proxy that answers with HTML is the case the classification must survive.
    func testMaps400WithUndecodableBodyStillClassifiesAsValidation() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 400, httpVersion: nil, headerFields: nil)!
            return (response, Data("<html><body>Bad Request</body></html>".utf8))
        }

        let request = PayabliRequest(method: .post, path: "/api/v2/MoneyIn/getpaid")
        do {
            _ = try await service().performV2(request, decoding: FakeData.self)
            XCTFail("Expected error")
        } catch let PayabliPaymentError.validation(err) {
            XCTAssertEqual(err.code, .validation)
            XCTAssertNil(err.title)
            XCTAssertNil(err.errors)
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
        } catch let PayabliPaymentError.decline(err) {
            XCTAssertEqual(err.rawCode, "D0001")
            XCTAssertEqual(err.reason, "Card Declined")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testMaps402WithPartialBodyKeepsTheDecline() async throws {
        StubURLProtocol.handler = { request in
            let json = """
            {"explanation":"Insufficient funds","action":"Try another card"}
            """
            let response = HTTPURLResponse(url: request.url!, statusCode: 402, httpVersion: nil, headerFields: nil)!
            return (response, Data(json.utf8))
        }

        let request = PayabliRequest(method: .post, path: "/api/v2/MoneyIn/getpaid")
        do {
            _ = try await service().performV2(request, decoding: FakeData.self)
            XCTFail("Expected error")
        } catch let PayabliPaymentError.decline(err) {
            XCTAssertNil(err.rawCode)
            XCTAssertEqual(err.reason, "Payment declined (402)")
            XCTAssertEqual(err.explanation, "Insufficient funds")
            XCTAssertEqual(err.action, "Try another card")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testMaps402WithUndecodableBodyStillClassifiesAsDecline() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 402, httpVersion: nil, headerFields: nil)!
            return (response, Data("<html>Payment Required</html>".utf8))
        }

        let request = PayabliRequest(method: .post, path: "/api/v2/MoneyIn/getpaid")
        do {
            _ = try await service().performV2(request, decoding: FakeData.self)
            XCTFail("Expected error")
        } catch let PayabliPaymentError.decline(err) {
            XCTAssertNil(err.rawCode)
            XCTAssertEqual(err.reason, "Payment declined (402)")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    func testMaps500WithUndecodableBodyStillClassifiesAsServer() async throws {
        StubURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 503, httpVersion: nil, headerFields: nil)!
            return (response, Data("<html>Service Unavailable</html>".utf8))
        }

        let request = PayabliRequest(method: .post, path: "/x")
        do {
            _ = try await service().performV2(request, decoding: FakeData.self)
            XCTFail("Expected error")
        } catch let PayabliPaymentError.server(err) {
            XCTAssertNil(err.title)
            XCTAssertEqual(err.reason, "Internal server error")
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
        } catch let PayabliPaymentError.server(err) {
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
            XCTAssertEqual(request.value(forHTTPHeaderField: "X-Caller-Header"), "kept")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
            return (response, Data("{}".utf8))
        }

        let request = PayabliRequest(
            method: .post,
            path: "/test",
            headers: ["X-Caller-Header": "kept", "Content-Type": "application/json"]
        )
        _ = try await service().perform(request)
    }

    /// A caller cannot choose the credential.
    ///
    /// Only the same-cased spelling is assertable here. `URLRequest.setValue` replaces
    /// case-insensitively, so with two keys differing only in case the survivor is whichever the
    /// dictionary yields last, and a test reading the result turns on iteration order. That guarantee
    /// is asserted on the request itself, by
    /// `testADifferentlyCasedCallerHeaderIsRemovedNotShadowed`.
    func testACallerSuppliedBearerIsNotWhatReachesTheWire() async throws {
        let stub = RecordingStub()
        stub.install()
        defer { stub.uninstall() }

        let request = PayabliRequest(
            method: .post,
            path: "/test",
            headers: ["Authorization": "Bearer caller-supplied"]
        )
        _ = try await service().perform(request)

        XCTAssertEqual(stub.sentTokens, [testToken])
    }
}

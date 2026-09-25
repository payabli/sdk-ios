@testable import PayabliSDKCore
@testable import PayabliSDKPayInPaymentFlow
import XCTest

/// The reversal route, which carries its identifier in its path and sends no body.
///
/// Its own class rather than a sixth section of the one above: that type is at the length the
/// linter allows, and a reversal is not a capture.
final class PayInVoidClientTests: XCTestCase {
    func testVoidSerializesPathAndSendsNoBody() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.canceledResponse)
        let client = PayInPaymentFlowClient(transport: transport)

        _ = try await client.void(transId: "10-7d9cd67d-2d5d-4cd7-a1b7-72b8b201ec13")

        let request = try await firstRequest(from: transport)
        XCTAssertEqual(request.path, "/api/v2/MoneyIn/void/10-7d9cd67d-2d5d-4cd7-a1b7-72b8b201ec13")
        XCTAssertTrue(request.query.isEmpty)
        XCTAssertNil(request.headers["Authorization"], "the client contributes no credential")
        XCTAssertNil(
            request.body,
            "the route takes what its path carries and nothing else, so an empty object is a different request"
        )
    }

    func testVoidEscapesPathSeparatorsInTransactionId() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.canceledResponse)
        let client = PayInPaymentFlowClient(transport: transport)

        _ = try await client.void(transId: "void/id 1")

        let request = try await firstRequest(from: transport)
        XCTAssertEqual(request.path, "/api/v2/MoneyIn/void/void%2Fid%201")
    }

    func testVoidRefusesABlankTransactionIdBeforeSendingAnything() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.canceledResponse)
        let client = PayInPaymentFlowClient(transport: transport)

        do {
            _ = try await client.void(transId: "   ")
            XCTFail("a blank transaction id must be refused")
        } catch let error as PayabliPayInPaymentFlowError {
            guard case .invalidInput = error else {
                return XCTFail("Wrong error: \(error)")
            }
            let requests = await transport.requests
            XCTAssertTrue(requests.isEmpty, "nothing may reach the service")
        }
    }

    /// `.` and `..` survive the encoder, which keeps the RFC 3986 unreserved set, so an identifier of
    /// either would name a route instead of a transaction.
    func testVoidRefusesADotSegmentAsATransactionId() async throws {
        for transId in [".", ".."] {
            let transport = MockPaymentCaptureTransport(responseBody: Self.canceledResponse)
            let client = PayInPaymentFlowClient(transport: transport)

            do {
                _ = try await client.void(transId: transId)
                XCTFail("\(transId) must be refused")
            } catch let error as PayabliPayInPaymentFlowError {
                guard case .invalidInput = error else {
                    return XCTFail("Wrong error for \(transId): \(error)")
                }
                let requests = await transport.requests
                XCTAssertTrue(requests.isEmpty, "nothing may reach the service for \(transId)")
            }
        }
    }

    /// A void answers `A0003` and calls itself canceled, where a capture answers `A0000`. An approval
    /// is not always the same act, so the code family decides rather than one literal.
    func testVoidApprovalIsNotReadAsARefusal() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.canceledResponse)
        let client = PayInPaymentFlowClient(transport: transport)

        let result = try await client.void(transId: "trans-1")

        XCTAssertEqual(result.code, "A0003")
        XCTAssertEqual(result.reason, "Canceled")
    }

    /// The service classifies what it will and will not reverse, so the SDK mirrors no rule of its own
    /// and surfaces the refusal it sent.
    func testAVoidTheServiceWillNotReverseCarriesItsReason() async throws {
        let transport = MockPaymentCaptureTransport(
            statusCode: 400,
            responseBody: """
            {
              "type": "about:blank",
              "title": "Bad Request",
              "status": 400,
              "detail": "Invalid transaction status",
              "instance": "/api/v2/MoneyIn/void/trans-1",
              "code": "E7037",
              "errors": {"transId": [{"message": "Invalid transaction status", "suggestion": ""}]},
              "token": null
            }
            """
        )
        let client = PayInPaymentFlowClient(transport: transport)

        do {
            _ = try await client.void(transId: "trans-1")
            XCTFail("a refusal must not read as a reversal")
        } catch let PayabliPaymentError.validation(refusal) {
            XCTAssertEqual(refusal.detail, "Invalid transaction status")
            XCTAssertEqual(refusal.rawCode, "E7037")
            XCTAssertEqual(refusal.errors?.keys.first, "transId")
        } catch {
            XCTFail("Wrong error: \(error)")
        }
    }

    private static let canceledResponse = """
    {
      "code": "A0003",
      "reason": "Canceled",
      "explanation": "Transaction canceled",
      "action": "No action required.",
      "data": {
        "paymentTransId": "3040-auth",
        "method": "card",
        "transStatus": 3,
        "operation": "Void",
        "responseData": {
          "resultCode": "A0003",
          "resultCodeText": "Canceled",
          "responsetext": "VOIDED"
        }
      },
      "token": null
    }
    """
}

/// Reserves the key the way the facade does, so these cases can exercise the client alone.
private extension PayInPaymentFlowClient {
    func void(transId: String) async throws -> PayabliPayInPaymentFlowResult {
        try await void(transId: transId, idempotencyKey: "reserved-by-test")
    }
}

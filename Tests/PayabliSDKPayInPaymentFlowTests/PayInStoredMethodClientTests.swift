@testable import PayabliSDKCore
@testable import PayabliSDKPayInPaymentFlow
import XCTest

/// What a charge to a stored method puts on the wire.
///
/// Its own class because the client's main suite is at the length the linter allows.
final class PayInStoredMethodClientTests: XCTestCase {
    func testAStoredMethodIsSentAsPayerInitiatedWithNoUsageType() async throws {
        let transport = MockPaymentCaptureTransport(responseBody: Self.approvedResponse)
        let client = PayInPaymentFlowClient(transport: transport)

        _ = try await client.capture(
            entryPoint: "entry",
            request: PayabliPayInPaymentFlowRequest(
                paymentDetails: PayabliPayInPaymentFlowPaymentDetails(totalAmount: 10),
                paymentMethod: .stored(PayabliPayInPaymentMethod.Stored(
                    method: .card,
                    storedMethodId: "stored-card-1"
                ))
            ),
            idempotencyKey: "idem-1"
        )

        let request = try await firstRequest(from: transport)
        let body = try XCTUnwrap(JSONSerialization.jsonObject(with: XCTUnwrap(request.body)) as? [String: Any])
        let paymentMethod = try XCTUnwrap(body["paymentMethod"] as? [String: Any])
        XCTAssertEqual(paymentMethod["method"] as? String, "card")
        XCTAssertEqual(paymentMethod["storedMethodId"] as? String, "stored-card-1")
        XCTAssertEqual(paymentMethod["initiator"] as? String, "payor")
        XCTAssertNil(paymentMethod["storedMethodUsageType"])
    }

    func testAStoredMethodIsACardOrABankAccount() {
        XCTAssertEqual(PayabliPayInPaymentFlowStoredMethodType.allCases.map(\.rawValue), ["card", "ach"])
    }

    private static let approvedResponse = """
    {
      "code": "A0000",
      "reason": "Approved",
      "data": {
        "paymentTransId": "3040-transaction",
        "method": "card",
        "transStatus": 1,
        "operation": "Sale",
        "responseData": {
          "resultCode": "A0000",
          "resultCodeText": "Approved"
        }
      },
      "token": null
    }
    """
}

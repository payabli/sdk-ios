import Foundation
import PayabliSDKCore

struct PaymentCaptureQAMockTransport: PayabliTransport {
    let result: PaymentMethodQAMockResult

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        switch result {
        case .success:
            return PayabliResponse(
                statusCode: 201,
                headers: ["Content-Type": "application/json"],
                body: Data(Self.successBody.utf8)
            )
        case .failure:
            return PayabliResponse(
                statusCode: 402,
                headers: ["Content-Type": "application/json"],
                body: Data(Self.failureBody.utf8)
            )
        }
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding _: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        throw PayabliGenericError(code: .unknown, reason: "performV2 is not used by payment capture QA")
    }

    private static let successBody = """
    {
      "code": "A0000",
      "reason": "Approved",
      "explanation": "Approved by QA mock transport.",
      "action": "No action required.",
      "data": {
        "paymentTransId": "qa-mock-payment-trans-id",
        "gatewayTransId": "qa-mock-gateway-trans-id",
        "orderId": "qa-capture-order",
        "method": "card",
        "transStatus": 1,
        "totalAmount": 12.34,
        "netAmount": 12.34,
        "feeAmount": 0,
        "operation": "Sale",
        "responseData": {
          "resultCode": "100",
          "resultCodeText": "Approved",
          "responsetext": "APPROVED",
          "authcode": "QA1234",
          "transactionid": "qa-mock-gateway-trans-id"
        },
        "source": "ios-payment-capture-qa",
        "isValidatedACH": false,
        "transactionTime": "2026-06-04T00:00:00Z",
        "ipAddress": "127.0.0.1"
      },
      "token": null
    }
    """

    private static let failureBody = """
    {
      "code": "D0200",
      "reason": "QA Mock Decline",
      "explanation": "The QA mock transport declined this transaction.",
      "action": "Use mock success or try a different payment method.",
      "data": null,
      "token": null
    }
    """
}

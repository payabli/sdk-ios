import Foundation
import PayabliSDKCore

struct PaymentMethodQAMockFailureTransport: PayabliTransport {
    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        PayabliResponse(
            statusCode: 400,
            headers: ["Content-Type": "application/json"],
            body: Data(Self.failureBody.utf8)
        )
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        throw PayabliGenericError(code: .unknown, reason: "performV2 is not used by payment method QA")
    }

    private static let failureBody = """
    {
      "isSuccess": false,
      "responseText": "Error",
      "responseCode": 6000,
      "responseData": {
        "explanation": "Invalid Card",
        "todoAction": "Please check your card details and try again."
      }
    }
    """
}

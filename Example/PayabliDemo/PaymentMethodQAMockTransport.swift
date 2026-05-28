import Foundation
import PayabliSDKCore

enum PaymentMethodQAMockResult {
    case success
    case failure
}

struct PaymentMethodQAMockTransport: PayabliTransport {
    let result: PaymentMethodQAMockResult

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        switch result {
        case .success:
            return PayabliResponse(
                statusCode: 200,
                headers: ["Content-Type": "application/json"],
                body: Data(Self.successBody.utf8)
            )
        case .failure:
            return PayabliResponse(
                statusCode: 400,
                headers: ["Content-Type": "application/json"],
                body: Data(Self.failureBody.utf8)
            )
        }
    }

    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        throw PayabliGenericError(code: .unknown, reason: "performV2 is not used by payment method QA")
    }

    private static let successBody = """
    {
      "isSuccess": true,
      "responseText": "Success",
      "responseData": {
        "referenceId": "qa-mock-stored-method",
        "resultCode": 1,
        "resultText": "Approved",
        "methodReferenceId": "qa-mock-method-reference",
        "customerId": 123456789
      }
    }
    """

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

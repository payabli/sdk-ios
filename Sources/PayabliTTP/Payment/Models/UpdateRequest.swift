import Foundation

/// Body for PATCH /api/v2/MoneyIn/update/{paymentTransId}
/// On success: sends the full Fiserv response as a dictionary.
/// On failure: sends error details.
/// Uses [String: Any] internally because the Fiserv response is dynamic JSON
/// that we forward as-is without mapping every field.
struct UpdateRequest {
    let fiservResponse: [String: Any]?
    let error: UpdateErrorPayload?

    struct UpdateErrorPayload {
        let title: String
        let description: String
        let failureReason: String
    }

    func toJSONData() throws -> Data {
        var payload: [String: Any] = [:]

        if let response: [String : Any] = fiservResponse {
            payload["fiservResponse"] = response
        }

        if let err: UpdateRequest.UpdateErrorPayload = error {
            payload["error"] = [
                "title": err.title,
                "description": err.description,
                "failureReason": err.failureReason
            ]
        }

        return try JSONSerialization.data(withJSONObject: payload)
    }
}

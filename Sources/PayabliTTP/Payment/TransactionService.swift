import Foundation

/// Handles all transaction orchestration API calls:
/// initiate (create transaction) and update (send Fiserv result).
/// Uses requestToken for authentication (obtained from ConfigResponse).
///
/// Future Phase 2 endpoints (refund, void, cancel) will be added here.
final class TransactionService {

    private let http: Networking

    /// Set after fetching config; required for all transaction calls.
    private(set) var requestToken: String?

    func configure(requestToken: String) {
        self.requestToken = requestToken
    }

    init(http: Networking) {
        self.http = http
    }

    /// Step 1 of charge: create a transaction record in Payabli backend.
    func initiateTransaction(body: InitiateRequest) async throws -> TransactionResponse {
        var request = try authenticatedRequest(endpoint: .initiate)
        request.httpBody = try http.encode(body)
        return try await http.execute(request)
    }

    /// Step 3 of charge: send the Fiserv SDK result back to Payabli backend.
    func updateTransaction(paymentTransId: String, body: UpdateRequest) async throws {
        var request = try authenticatedRequest(endpoint: .update(paymentTransId: paymentTransId))
        request.httpBody = try body.toJSONData()
        try await http.executeVoid(request)
    }

    // MARK: - Internal

    private func authenticatedRequest(endpoint: Endpoint) throws -> URLRequest {
        guard let token = requestToken else {
            throw PayabliTTPError.notInitialized
        }
        return try http.buildRequest(endpoint: endpoint, authHeader: ("requestToken", token))
    }
}

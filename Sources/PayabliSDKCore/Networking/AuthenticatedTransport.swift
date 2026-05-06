import Foundation

/// Decorator that injects the `Authorization: Bearer <token>` header on
/// every outgoing request and handles HTTP 401 with a single
/// refresh-and-retry. After two consecutive 401s, throws
/// `PayabliGenericError(.tokenExpired)`.
///
/// Endpoint clients that need bearer auth depend on this transport rather
/// than open-coding the header / retry dance themselves.
public struct AuthenticatedTransport: PayabliTransport {
    private let base: any PayabliTransport
    private let auth: PayabliAuth

    public init(base: any PayabliTransport, auth: PayabliAuth) {
        self.base = base
        self.auth = auth
    }

    public func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        let token = await auth.currentAccessToken()
        let firstAttempt = try await base.perform(authorize(request, with: token))

        guard firstAttempt.statusCode == 401 else { return firstAttempt }

        let refreshed = try await auth.invalidateAndRefresh()
        let secondAttempt = try await base.perform(authorize(request, with: refreshed))
        if secondAttempt.statusCode == 401 {
            throw PayabliGenericError(
                code: .tokenExpired,
                reason: "Refresh token rejected"
            )
        }
        return secondAttempt
    }

    public func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        let response = try await perform(request)
        try mapPayabliHTTPError(response: response)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(PayabliV2Envelope<T>.self, from: response.body)
        } catch {
            throw PayabliGenericError(
                code: .decodingError,
                reason: "Failed to decode v2 envelope",
                underlying: error
            )
        }
    }

    private func authorize(_ request: PayabliRequest, with token: String) -> PayabliRequest {
        var headers = request.headers
        headers["Authorization"] = "Bearer \(token)"
        return PayabliRequest(
            method: request.method,
            path: request.path,
            query: request.query,
            headers: headers,
            body: request.body
        )
    }
}

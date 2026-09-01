import Foundation

/// Attaches `Authorization: Bearer` to every outbound request, overriding a caller's own.
///
/// The token is read per request.
struct BearerDecoration: PayabliRequestDecoration {
    private static let headerName = "Authorization"
    private static let scheme = "Bearer "

    private let readToken: @Sendable () async throws -> String

    init(readToken: @escaping @Sendable () async throws -> String) {
        self.readToken = readToken
    }

    func decorate(_ request: PayabliRequest) async throws -> PayabliRequest {
        let token = try await readToken()
        try Self.validate(token)
        SentToken.current?.record(token)
        return request.withHeaders([Self.headerName: Self.scheme + token])
    }

    /// Refuses a token that cannot be sent: blank, or not a legal header value.
    private static func validate(_ token: String) throws {
        guard !token.isBlank else {
            throw PayabliGenericError(
                code: .tokenExpired,
                reason: "Access token unusable",
                detail: "The token source returned a blank token."
            )
        }
        guard token.isHeaderSafe else {
            throw PayabliGenericError(
                code: .tokenMalformed,
                reason: "Access token unusable",
                detail: "The token source returned a token that cannot be an HTTP header value."
            )
        }
    }
}

import Foundation

/// Attaches `Authorization: Bearer` to every outbound request, overriding a caller's own.
///
/// The token is read per request, so a replay after a refresh carries the new one.
///
/// `readToken` is a closure, so a surface whose credential comes from a per-call provider can supply
/// one and get the credential without the recovery layer above it.
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
        // Recorded after validation, so the layer that reports a rejection names a token that was sent.
        SentToken.current?.record(token)
        return request.withHeaders([Self.headerName: Self.scheme + token])
    }

    /// The only place every token source is seen, so a `readToken` the caller supplied meets the same
    /// checks as a token from the config or a refresh.
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

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
        // Recorded for the layer that reports which token a rejection refused.
        SentToken.current?.record(token)
        return request.withHeaders([Self.headerName: Self.scheme + token])
    }
}

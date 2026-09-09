import Foundation

/// Attaches `Authorization: Bearer` to every outbound request, overriding a caller's own.
///
/// The token is read per request and is not checked here. The only thing that reaches this is a
/// holder that checks every token it installs, so a blank or unsendable one cannot arrive.
struct BearerDecoration: PayabliRequestDecoration {
    private static let headerName = "Authorization"
    private static let scheme = "Bearer "

    private let readToken: @Sendable () async throws -> String

    init(readToken: @escaping @Sendable () async throws -> String) {
        self.readToken = readToken
    }

    func decorate(_ request: PayabliRequest) async throws -> PayabliRequest {
        let token = try await readToken()
        SentToken.current?.record(token)
        return request.withHeaders([Self.headerName: Self.scheme + token])
    }
}

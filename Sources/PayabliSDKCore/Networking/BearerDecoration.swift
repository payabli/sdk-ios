import Foundation

/// Attaches `Authorization: Bearer` to every outbound request, overriding a caller's own.
///
/// The token is read per request and is not checked here. The only thing that reaches this is a
/// holder that checks every token it installs, so a blank or unsendable one cannot arrive.
///
/// A request that requires a held credential is refused when none is held, and never starts a provider call.
struct BearerDecoration: PayabliRequestDecoration {
    private static let headerName = "Authorization"
    private static let scheme = "Bearer "

    private let readToken: @Sendable () async throws -> String
    private let readHeldToken: @Sendable () async -> String?

    /// - Parameter readToken: reads the token to send, minting one when none is held.
    /// - Parameter readHeldToken: reads the token already held, without minting, for a request that requires one.
    init(
        readToken: @escaping @Sendable () async throws -> String,
        readHeldToken: @escaping @Sendable () async -> String?
    ) {
        self.readToken = readToken
        self.readHeldToken = readHeldToken
    }

    func decorate(_ request: PayabliRequest) async throws -> PayabliRequest {
        let token: String
        if request.requiresHeldCredential {
            guard let held = await readHeldToken() else { throw Self.noneHeld() }
            token = held
        } else {
            token = try await readToken()
        }
        SentToken.current?.record(token)
        return request.withHeaders([Self.headerName: Self.scheme + token])
    }

    /// The refusal of a request that requires a held credential when none is ready to send.
    ///
    /// - Returns: the `missingToken` refusal.
    static func noneHeld() -> PayabliGenericError {
        PayabliGenericError(
            type: .missingToken,
            reason: "Access token unavailable",
            detail: "No access token is ready to send, and this request does not obtain one."
        )
    }
}

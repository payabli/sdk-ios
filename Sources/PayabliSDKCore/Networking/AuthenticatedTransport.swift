import Foundation

/// Handles an HTTP 401 with a single refresh-and-retry. After two consecutive 401s, throws
/// `PayabliGenericError(.tokenExpired)`.
///
/// The bearer is attached by `base`'s chain, not here, so a request that skips this layer still
/// carries its credential.
struct AuthenticatedTransport: PayabliTransport {
    private let base: any PayabliTransport
    private let auth: PayabliAuth
    private let logger: PayabliLogger

    /// `.network`, not `.auth`: recovering, or giving up on it, is this layer's decision and not the
    /// holder's. The logger is required rather than defaulted, so no composition can build its own and
    /// leave a caller's substitution reaching nothing.
    init(base: any PayabliTransport, auth: PayabliAuth, logger: PayabliLogger) {
        self.base = base
        self.auth = auth
        self.logger = logger
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        let stamped = SentToken()
        let firstAttempt = try await SentToken.$current.withValue(stamped) {
            try await base.perform(request)
        }

        guard firstAttempt.statusCode == 401 else { return firstAttempt }

        logger.info("credential rejected: attempting recovery (\(request.method.rawValue) 401)")

        // The token the chain stamped. A fresh read covers a chain that stamped nothing.
        let rejected: String = if let sent = stamped.value {
            sent
        } else {
            await auth.currentAccessToken()
        }
        _ = try await auth.invalidateAndRefresh(rejectedToken: rejected)

        // Re-entering the transport re-runs the chain, which reads the refreshed token.
        logger.debug("replaying \(request.method.rawValue) under the current credential")
        let replayed = SentToken()
        let secondAttempt = try await SentToken.$current.withValue(replayed) {
            try await base.perform(request)
        }
        if secondAttempt.statusCode == 401 {
            logger.warning(
                "recovery exhausted: the replay was refused too (\(request.method.rawValue) 401)"
            )
            throw PayabliGenericError(
                code: .tokenExpired,
                reason: "Refresh token rejected"
            )
        }
        return secondAttempt
    }

    /// `base`'s overload maps a 401 to a typed error, so this decodes after its own `perform`.
    func performV2<T: Decodable & Sendable>(
        _ request: PayabliRequest,
        decoding: T.Type
    ) async throws -> PayabliV2Envelope<T> {
        let response = try await perform(request)
        try mapPayabliHTTPError(response: response)
        return try decodePayabliV2Envelope(T.self, from: response)
    }
}

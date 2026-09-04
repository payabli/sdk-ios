import Foundation

/// Replaces a refused credential once, and replays the request under the new one where that is safe.
/// A second refusal is terminal.
///
/// The bearer is attached by `base`'s chain, not here, so a request that skips this layer still
/// carries its credential.
///
/// Which statuses count as a refusal is `recovery`'s; whether the request may be sent again is this
/// layer's. Keeping them apart is what stops a widened refusal from also widening what gets replayed.
struct AuthenticatedTransport: PayabliTransport {
    private let base: any PayabliTransport
    private let auth: PayabliAuth
    private let recovery: any AuthRecoveryPolicy
    private let logger: PayabliLogger

    /// `.network`, not `.auth`: recovering, or giving up on it, is this layer's decision and not the
    /// holder's. The logger is required rather than defaulted, so no composition can build its own and
    /// leave a caller's substitution reaching nothing.
    init(
        base: any PayabliTransport,
        auth: PayabliAuth,
        recovery: any AuthRecoveryPolicy = DefaultAuthRecoveryPolicy(),
        logger: PayabliLogger
    ) {
        self.base = base
        self.auth = auth
        self.recovery = recovery
        self.logger = logger
    }

    func perform(_ request: PayabliRequest) async throws -> PayabliResponse {
        let stamped = SentToken()
        let firstAttempt = try await SentToken.$current.withValue(stamped) {
            try await base.perform(request)
        }

        guard recovery.isCredentialRejection(firstAttempt) else { return firstAttempt }

        logger.info(
            "credential rejected: attempting recovery"
                + " (\(request.method.rawValue) \(firstAttempt.statusCode))"
        )

        // The token the chain stamped. A fresh read covers a chain that stamped nothing.
        let rejected: String = if let sent = stamped.value {
            sent
        } else {
            await auth.currentAccessToken()
        }
        _ = try await auth.invalidateAndRefresh(rejectedToken: rejected)

        // Refreshing first and deciding after: a refused credential is worth replacing whether or not
        // this particular request may be sent again, so the next one starts from a clean one.
        guard mayReplay(request, rejectedBy: firstAttempt) else {
            logger.warning(
                "replay declined: the method is not idempotent and the status was not 401"
                    + " (\(request.method.rawValue) \(firstAttempt.statusCode))"
            )
            return firstAttempt
        }

        // Re-entering the transport re-runs the chain, which reads the refreshed token.
        logger.debug("replaying \(request.method.rawValue) under the current credential")
        let replayed = SentToken()
        let secondAttempt = try await SentToken.$current.withValue(replayed) {
            try await base.perform(request)
        }
        if recovery.isCredentialRejection(secondAttempt) {
            logger.warning(
                "recovery exhausted: the replay was refused too"
                    + " (\(request.method.rawValue) \(secondAttempt.statusCode))"
            )
            throw recovery.exhausted()
        }
        return secondAttempt
    }

    /// Whether sending `request` a second time is defensible after `rejection`.
    ///
    /// A 401 is refused before the request is processed, so replaying one cannot execute it twice. No
    /// other status carries that argument, which leaves the method's own idempotence as the only signal
    /// for a widened rejection. It lives here and not on `AuthRecoveryPolicy`: a hook there would let
    /// whoever widened what counts as a rejection widen what gets replayed along with it.
    private func mayReplay(_ request: PayabliRequest, rejectedBy rejection: PayabliResponse) -> Bool {
        rejection.statusCode == 401 || request.method.isIdempotent
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

/// RFC 9110 Section 9.2.2: "Of the request methods defined by this specification, PUT, DELETE, and safe
/// request methods are idempotent", with Section 9.2.1 naming GET, HEAD, OPTIONS and TRACE as safe.
///
/// So POST and PATCH are excluded, PATCH despite looking like a sibling of PUT. Private to this file
/// because one call site needs it, and a property on the shared method type would owe a disposition on
/// the other platform for no gain.
private extension HTTPMethod {
    var isIdempotent: Bool {
        switch self {
        case .get, .put, .delete: true
        case .post, .patch: false
        }
    }
}

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
    ///
    /// - Parameter base: the transport performing each attempt, whose chain attaches the bearer.
    /// - Parameter auth: the holder that replaces a refused credential, once.
    /// - Parameter recovery: what counts as a credential refusal; 401 only, by default.
    /// - Parameter logger: the logger, required rather than defaulted, so a caller's substitution reaches it.
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
        // Fails without a round trip once the holder is finished. The holder refuses a new mint on its own,
        // so this saves a send rather than guarding one.
        if let failure = auth.terminalFailure {
            throw failure
        }

        let stamped = SentToken()
        let firstAttempt = try await SentToken.$current.withValue(stamped) {
            try await base.perform(request)
        }

        guard recovery.isCredentialRejection(firstAttempt), !request.isCallerRefusal(firstAttempt) else {
            return firstAttempt
        }

        if firstAttempt.statusCode == 401 {
            PayabliSendMark.current?.lower()
        }

        // Above the refresh, which is the half that breaks a pinned credential. The caller renews the token
        // once the sequence it belongs to has ended.
        if request.pinsCredential {
            logger.warning(
                "recovery declined: the route pins the credential it was sent"
                    + " (\(request.method.rawValue) \(firstAttempt.statusCode))"
            )
            if let sent = stamped.value {
                await auth.recordPinnedRefusal(of: sent)
            }
            return firstAttempt
        }

        logger.info(
            "credential rejected: attempting recovery"
                + " (\(request.method.rawValue) \(firstAttempt.statusCode))"
        )

        // The token the chain stamped, falling back to the one held for a chain that stamped
        // nothing. Held rather than minted: a token obtained here would name a credential that no
        // request carried, and holding none means there is nothing to replace.
        let sentOrHeld: String? = if let sent = stamped.value {
            sent
        } else {
            await auth.heldToken()
        }
        guard let rejected = sentOrHeld else {
            logger.warning("credential rejected, and none was sent: nothing to recover")
            return firstAttempt
        }
        _ = try await PayabliSendMark.$current.withValue(nil) {
            try await auth.invalidateAndRefresh(rejectedToken: rejected)
        }

        // Asked here rather than inside the holder, because a refresh answers from several places: a
        // caller inside its own provider gets the current token, a token another request already rotated
        // comes back without waiting, and only the joining path passes a check. Sending the request again
        // is this layer's decision, so this is where the caller's cancellation has to stop it.
        try Task.checkCancellation()

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
        if recovery.isCredentialRejection(secondAttempt), !request.isCallerRefusal(secondAttempt) {
            logger.warning(
                "recovery exhausted: the replay was refused too"
                    + " (\(request.method.rawValue) \(secondAttempt.statusCode))"
            )
            throw await finishingTheSession(refusedOn: replayed)
        }
        return secondAttempt
    }

    /// Finishes the session on a replay refused in turn, unless its token has moved on or is being replaced: then the
    /// refusal is about a token, and finishing would end a session whose next token works. The holder decides and
    /// records that in one turn.
    ///
    /// - Parameter replayed: the token the refused replay carried, if one was stamped.
    /// - Returns: the failure the caller throws.
    private func finishingTheSession(refusedOn replayed: SentToken) async -> PayabliGenericError {
        let exhausted = recovery.exhausted()
        if let sent = replayed.value {
            _ = await auth.finishIfSettled(on: sent, with: exhausted)
        } else {
            // Nothing stamped means the replay carried no bearer, which is not a state to be lenient about.
            await auth.finish(with: exhausted)
        }
        return exhausted
    }

    /// Whether sending `request` a second time is defensible after `rejection`.
    /// A 401 was refused before the request was processed, so replaying one cannot execute it twice.
    /// It lives here rather than on `AuthRecoveryPolicy`, so widening rejections does not widen what gets replayed.
    ///
    /// - Parameter request: the request whose replay is decided, its method the signal for a non-401 status.
    /// - Parameter rejection: the response that refused the credential, whose status carries the 401 argument.
    /// - Returns: whether the replay may run.
    private func mayReplay(_ request: PayabliRequest, rejectedBy rejection: PayabliResponse) -> Bool {
        rejection.statusCode == 401 || request.method.isIdempotent
    }

    /// `base`'s overload maps a 401 to a typed error, so this decodes after its own `perform`.
    ///
    /// - Parameter request: the request to send through this transport's own recovery.
    /// - Parameter decoding: the type the envelope's `data` decodes as.
    /// - Returns: the decoded envelope, after a non-2xx answer already became a typed error.
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
/// So POST and PATCH are excluded.
private extension HTTPMethod {
    var isIdempotent: Bool {
        switch self {
        case .get, .put, .delete: true
        case .post, .patch: false
        }
    }
}

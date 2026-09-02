import Foundation

public actor PayabliAuth {
    private let config: PayabliConfig
    private let logger: PayabliLogger

    private var currentToken: String
    /// Guards against concurrent refresh attempts. If a refresh is in flight, other callers await
    /// the same Task result, except one already inside this holder's own provider call.
    private var inFlightRefresh: Task<String, Error>?
    /// Names the refresh `inFlightRefresh` is running, so a mark that outlived its own refresh
    /// is ignored rather than answering a later rejection.
    private var inFlightRefreshID: UUID?

    /// Multicasts every successful token rotation. Producers append on every
    /// refresh; consumers iterate as long as they want.
    private var tokenChangeContinuations: [UUID: AsyncStream<String>.Continuation] = [:]

    public init(config: PayabliConfig) {
        self.init(config: config, logger: PayabliLogger(category: .auth))
    }

    /// Internal, so it widens what a test can construct and not what production can. The logger is
    /// required rather than defaulted: a holder that built its own would leave a caller's substitution
    /// reaching nothing, and nothing would report it.
    init(config: PayabliConfig, logger: PayabliLogger) {
        self.config = config
        self.logger = logger
        self.currentToken = config.accessToken
    }

    /// Returns the current access token. Never throws synchronously — token
    /// refresh only happens after a 401 via `invalidateAndRefresh(rejectedToken:)`.
    public func currentAccessToken() -> String {
        currentToken
    }

    /// Reports `rejectedToken` as refused and returns the token to use instead.
    /// Callers invoke this after receiving HTTP 401, then retry once.
    ///
    /// Passing the token that was actually rejected is what makes a staggered
    /// rejection cheap: two requests sent with the same token can have their 401s
    /// arrive far apart, and the later one must not refresh again on a token that
    /// has already rotated, which would discard the rotation the first one obtained.
    ///
    /// A caller already inside this holder's own provider call is answered first, with the token
    /// currently held: the refresh it would otherwise join is the one waiting on it. That holds at
    /// any depth, where one provider calls a second session whose provider calls back into this one.
    /// A mark naming a refresh that has already finished is not one of these and takes the ordinary
    /// path, so a task a provider left running cannot answer for a refresh that is over.
    ///
    /// The in-flight join comes before the already-rotated check, because the
    /// current token may itself be the one under refresh and handing it back would
    /// return a credential already known to be rejected.
    ///
    /// If no provider is configured, throws `PayabliGenericError(.tokenExpired)`
    /// so the caller can surface a re-authentication prompt.
    public func invalidateAndRefresh(rejectedToken: String) async throws -> String {
        if let refreshID = inFlightRefreshID, RefreshInProgress.carries(self, refresh: refreshID) {
            return currentToken
        }

        if let existing = inFlightRefresh {
            return try await existing.value
        }

        guard currentToken == rejectedToken else {
            let rotated = currentToken
            logger.info("Access token already rotated; reusing the current one")
            return rotated
        }

        guard let provider = config.tokenProvider else {
            logger.error("Access token rejected and no tokenProvider configured")
            throw PayabliGenericError(
                code: .tokenExpired,
                reason: "Access token expired",
                detail: "Host app did not supply a tokenProvider; re-initialize the SDK with a fresh accessToken."
            )
        }

        // Validation, redaction and the install are all inside the task, because a joiner
        // at the top of this method awaits this same value. So a joiner receives a checked
        // token, never the host's own error text, and never resumes before the token is
        // installed — which matters because the decoration chain reads the holder again on
        // the replay.
        let refreshID = UUID()
        let task = Task<String, Error> { [logger] in
            logger.info("Refreshing access token via partner tokenProvider")
            let minted: String
            do {
                minted = try await RefreshInProgress.withMark(holder: self, refresh: refreshID) {
                    try await provider()
                }
            } catch {
                // Every throw from the provider lands here, this SDK's own error type
                // included: it is host code whatever it chose to throw.
                logger.error("The token provider failed")
                throw PayabliGenericError(
                    code: .tokenExpired,
                    reason: "Token refresh failed",
                    underlying: RedactedCause(error)
                )
            }
            do {
                try Self.validate(minted, against: rejectedToken)
            } catch {
                logger.error("The minted token was refused before it was committed")
                throw error
            }
            self.commit(minted)
            return minted
        }
        inFlightRefresh = task
        inFlightRefreshID = refreshID

        do {
            return try await task.value
        } catch {
            inFlightRefresh = nil
            inFlightRefreshID = nil
            throw error
        }
    }

    /// Installs the minted token and announces the rotation. Called only once the
    /// token has passed `validate(_:against:)`, so nothing here can publish a
    /// rotation that did not happen.
    private func commit(_ fresh: String) {
        currentToken = fresh
        inFlightRefresh = nil
        inFlightRefreshID = nil
        logger.info("Access token refreshed")
        for (_, continuation) in tokenChangeContinuations {
            continuation.yield(fresh)
        }
    }

    /// Throws rather than let a minted token be committed.
    ///
    /// A blank one becomes the session's credential and every later request goes out
    /// unauthenticated. A token equal to the one just refused publishes a rotation
    /// that did not happen and hands the caller a credential the server has already
    /// rejected; because `currentToken` would be unchanged, the next rejection starts
    /// another provider call instead of taking the already-rotated path, so a
    /// provider that keeps returning it costs one call per 401 with no end.
    private static func validate(_ fresh: String, against rejectedToken: String) throws {
        guard !fresh.isBlank else {
            throw PayabliGenericError(
                code: .tokenExpired,
                reason: "Token refresh failed",
                detail: "The tokenProvider returned a blank token."
            )
        }
        guard fresh.isHeaderSafe else {
            throw PayabliGenericError(
                code: .tokenMalformed,
                reason: "Token refresh failed",
                detail: "The tokenProvider returned a token that cannot be an HTTP header value."
            )
        }
        guard fresh != rejectedToken else {
            throw PayabliGenericError(
                code: .tokenExpired,
                reason: "Token refresh failed",
                detail: "The tokenProvider returned the token the server rejected."
            )
        }
    }

    /// Test/dev convenience — resets the cached token to the initial value from
    /// `PayabliConfig`. Not part of the public API contract.
    public func reset() {
        currentToken = config.accessToken
        inFlightRefresh = nil
        inFlightRefreshID = nil
    }

    /// AsyncStream that emits whenever `invalidateAndRefresh(rejectedToken:)` commits a new token.
    /// Each call returns an independent stream — multiple subscribers each
    /// receive every subsequent token.
    public func tokenChanges() -> AsyncStream<String> {
        let id = UUID()
        return AsyncStream { continuation in
            tokenChangeContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task { await self?.removeTokenChangeContinuation(id: id) }
            }
        }
    }

    private func removeTokenChangeContinuation(id: UUID) {
        tokenChangeContinuations.removeValue(forKey: id)
    }
}

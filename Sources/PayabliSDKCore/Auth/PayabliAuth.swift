import Foundation

actor PayabliAuth {
    private let config: PayabliConfig
    private let logger: PayabliLogger

    /// Nil until the first request asks for one. The provider is the only source, so there is no
    /// state in which a token is held that the holder did not check.
    private var currentToken: String?
    /// Guards against concurrent provider calls. If one is in flight, other callers await the same
    /// Task result, except one already inside this holder's own provider call.
    private var inFlightMint: Task<String, Error>?
    /// Names the call `inFlightMint` is running, so a mark that outlived its own call is ignored
    /// rather than answering a later rejection.
    private var inFlightMintID: UUID?

    init(config: PayabliConfig) {
        self.init(config: config, logger: PayabliLogger(category: .auth))
    }

    /// The logger is required rather than defaulted: a holder that built its own would leave a
    /// caller's substitution reaching nothing, and nothing would report it.
    init(config: PayabliConfig, logger: PayabliLogger) {
        self.config = config
        self.logger = logger
    }

    /// The token to send, minting one when none is held.
    ///
    /// The first read has nothing to return, so it calls the provider exactly as a rejection does and
    /// shares that call: concurrent cold requests spend one provider call between them, not one each.
    func currentAccessToken() async throws -> String {
        if let held = currentToken {
            return held
        }

        if let mintID = inFlightMintID, RefreshInProgress.carries(self, refresh: mintID) {
            // A provider that issues its own request through the SDK arrives here, and on the cold
            // path there is no held token to answer it with. Refusing names the cycle; joining would
            // await the call this caller is inside.
            logger.error("The token provider requested a token before returning its first one")
            throw PayabliGenericError(
                code: .tokenExpired,
                reason: "Access token unavailable",
                detail: "The tokenProvider made a request that needs the token it was asked to supply."
            )
        }

        if let existing = inFlightMint {
            return try await join(existing)
        }

        return try await mint(replacing: nil)
    }

    /// The token held right now, without minting one.
    ///
    /// For the recovery path, which needs to name what was sent rather than obtain something to
    /// send. Minting here would name a credential no request carried.
    func heldToken() -> String? {
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
    /// currently held: the call it would otherwise join is the one waiting on it. That holds at
    /// any depth, where one provider calls a second session whose provider calls back into this one.
    /// A mark naming a call that has already finished is not one of these and takes the ordinary
    /// path, so a task a provider left running cannot answer for a call that is over.
    ///
    /// The in-flight join comes before the already-rotated check, because the
    /// current token may itself be the one under refresh and handing it back would
    /// return a credential already known to be rejected.
    func invalidateAndRefresh(rejectedToken: String) async throws -> String {
        if let mintID = inFlightMintID, RefreshInProgress.carries(self, refresh: mintID) {
            guard let held = currentToken else {
                logger.error("The token provider requested a token before returning its first one")
                throw PayabliGenericError(
                    code: .tokenExpired,
                    reason: "Access token unavailable",
                    detail: "The tokenProvider made a request that needs the token it was asked to supply."
                )
            }
            return held
        }

        if let existing = inFlightMint {
            return try await join(existing)
        }

        if let held = currentToken, held != rejectedToken {
            logger.info("Access token already rotated; reusing the current one")
            return held
        }

        return try await mint(replacing: rejectedToken)
    }

    /// Calls the provider, checks what it returned, and installs it, with one call shared between
    /// every caller waiting on it.
    ///
    /// `replacing` is the token a rejection named, and nil on the first mint. It is what
    /// `check(_:replacing:)` refuses a repeat of.
    ///
    /// Validation, redaction and the install are all inside the task, because a joiner awaits this
    /// same value. So a joiner receives a checked token, never the host's own error text, and never
    /// resumes before the token is installed, which matters because the decoration chain reads the
    /// holder again on the replay.
    private func mint(replacing rejectedToken: String?) async throws -> String {
        let provider = config.tokenProvider
        let mintID = UUID()
        let task = Task<String, Error> { [logger] in
            logger.info("Requesting an access token from the partner tokenProvider")
            let minted: String
            do {
                minted = try await RefreshInProgress.withMark(holder: self, refresh: mintID) {
                    try await provider()
                }
            } catch {
                // Every throw from the provider lands here, this SDK's own error type
                // included: it is host code whatever it chose to throw.
                logger.error("The token provider failed")
                throw PayabliGenericError(
                    code: .tokenExpired,
                    reason: "Token request failed",
                    underlying: RedactedCause(error)
                )
            }
            do {
                try Self.check(minted, replacing: rejectedToken)
            } catch {
                logger.error("The minted token was refused before it was committed")
                throw error
            }
            self.commit(minted, mintID: mintID)
            return minted
        }
        inFlightMint = task
        inFlightMintID = mintID

        do {
            return try await join(task)
        } catch {
            releaseMint(mintID)
            throw error
        }
    }

    /// Waits for a mint already under way and answers with what it produced, unless this caller was
    /// cancelled while waiting.
    ///
    /// The mint itself runs on: it is shared, so one waiter going away must not take the credential from
    /// the others. Only this caller stops.
    ///
    /// Cancellation is raised rather than returned because a caller who is cancelled and handed a token
    /// carries on with it, which on the recovery path means sending the request again. `Task.value` does
    /// not observe the awaiting task's cancellation, so nothing else here would notice.
    private func join(_ mint: Task<String, Error>) async throws -> String {
        // The result rather than the value, so a mint that fails does not throw past the check. A caller
        // cancelled while a provider was failing is cancelled, not told what the provider said: the
        // failure belongs to whoever is still waiting for it.
        let outcome = await mint.result
        try Task.checkCancellation()
        return try outcome.get()
    }

    /// Drops the in-flight mark, and only for the call that owns it.
    ///
    /// A call whose mark has already been replaced clears nothing, so a finished mint cannot
    /// discard a later one's task and leave its joiners waiting on a task no mark names.
    private func releaseMint(_ mintID: UUID) {
        guard inFlightMintID == mintID else { return }
        inFlightMint = nil
        inFlightMintID = nil
    }

    /// Installs the minted token. Called only once the token has passed `check(_:replacing:)`, so
    /// nothing here can install one that was refused.
    private func commit(_ fresh: String, mintID: UUID) {
        currentToken = fresh
        releaseMint(mintID)
        logger.info("Access token installed")
    }

    /// Throws rather than let a minted token be committed. Every token this holder installs passes
    /// here, so nothing downstream re-checks one.
    ///
    /// A blank one becomes the session's credential and every later request goes out
    /// unauthenticated. A token equal to the one just refused publishes a rotation
    /// that did not happen and hands the caller a credential the server has already
    /// rejected; because `currentToken` would be unchanged, the next rejection starts
    /// another provider call instead of taking the already-rotated path, so a
    /// provider that keeps returning it costs one call per 401 with no end.
    private static func check(_ fresh: String, replacing rejectedToken: String?) throws {
        guard !fresh.isBlank else {
            throw PayabliGenericError(
                code: .tokenExpired,
                reason: "Token request failed",
                detail: "The tokenProvider returned a blank token."
            )
        }
        guard fresh.isHeaderSafe else {
            throw PayabliGenericError(
                code: .tokenMalformed,
                reason: "Token request failed",
                detail: "The tokenProvider returned a token that cannot be an HTTP header value."
            )
        }
        guard fresh != rejectedToken else {
            throw PayabliGenericError(
                code: .tokenExpired,
                reason: "Token request failed",
                detail: "The tokenProvider returned the token the server rejected."
            )
        }
    }

    /// Drops the held token and any call in flight, so the next read mints again.
    func reset() {
        currentToken = nil
        inFlightMint = nil
        inFlightMintID = nil
    }
}

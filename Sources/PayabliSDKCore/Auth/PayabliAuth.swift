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
    private var pinnedRefusal: String?
    /// The refusal this holder raised into the provider call named by `mintID`, so that call reports `reentered` only
    /// when the provider threw that refusal back, and `threw` for an error it built in its place.
    private var reentryRefusal: (mintID: UUID, error: PayabliGenericError)?

    /// What times the provider bound below. A parameter rather than a hardwired `SystemRetryClock()`
    /// so a test can race the deadline deterministically instead of waiting thirty real seconds —
    /// the same reason `Retry.run` takes one.
    private let clock: any RetryClock

    /// Fired after a caller joined an in-flight mint. Nil in production; a test injects a counter
    /// to gate a synchronized deadline on every intended joiner having arrived.
    private let onJoinedInFlightMint: (@Sendable () -> Void)?

    /// Why this holder is finished, or nil while it still works. Written only inside this actor, so no mint
    /// can start between deciding and recording. Readable without awaiting.
    private nonisolated let finished = FinishedSlot()

    /// Non-nil once this holder is finished: a token refreshed after a rejection was refused in turn.
    nonisolated var terminalFailure: PayabliGenericError? {
        finished.failure
    }

    init(config: PayabliConfig) {
        self.init(config: config, logger: PayabliLogger(category: .auth))
    }

    /// The logger is required rather than defaulted: a holder that built its own would leave a
    /// caller's substitution reaching nothing, and nothing would report it.
    ///
    /// - Parameter config: the configuration whose `tokenProvider` mints every token.
    /// - Parameter logger: where the holder reports its provider calls, so a substitution reaches them.
    /// - Parameter clock: what times the provider bound; a test injects one to race the deadline.
    /// - Parameter onJoinedInFlightMint: fired after a caller joined an in-flight mint; nil in production.
    init(
        config: PayabliConfig,
        logger: PayabliLogger,
        clock: any RetryClock = SystemRetryClock(),
        onJoinedInFlightMint: (@Sendable () -> Void)? = nil
    ) {
        self.config = config
        self.logger = logger
        self.clock = clock
        self.onJoinedInFlightMint = onJoinedInFlightMint
    }

    /// The token to send, minting one when none is held.
    ///
    /// The first read has nothing to return, so it calls the provider exactly as a rejection does and
    /// shares that call: concurrent cold requests spend one provider call between them, not one each.
    ///
    /// - Returns: the access token to send, minted when none is held and the call shared with cold joiners.
    func currentAccessToken() async throws -> String {
        if let held = currentToken {
            return held
        }

        if let mintID = inFlightMintID, RefreshInProgress.carries(self, refresh: mintID) {
            // A provider that issues its own request through the SDK arrives here, and on the cold
            // path there is no held token to answer it with. Refusing names the cycle; joining would
            // await the call this caller is inside.
            logger.error("The token provider requested a token before returning its first one")
            throw refuseReentry(into: mintID)
        }

        if let failure = terminalFailure {
            throw failure
        }

        if let existing = inFlightMint {
            onJoinedInFlightMint?()
            return try await join(existing)
        }

        return try await mint(replacing: nil)
    }

    /// Marks this holder finished when `token` is still the one it would send and no mint is in flight.
    ///
    /// A token that has moved on, or is being replaced, says nothing about the session, so a rejection of
    /// it finishes nothing.
    ///
    /// - Parameters:
    ///   - token: The credential the rejection arrived on.
    ///   - failure: What finished the holder.
    /// - Returns: Whether the holder was marked finished.
    func finishIfSettled(on token: String, with failure: PayabliGenericError) -> Bool {
        guard inFlightMint == nil, currentToken == token else { return false }
        finished.failure = failure
        return true
    }

    /// Marks this holder finished outright, for a rejection no rotation could have fixed.
    ///
    /// - Parameter failure: What finished the holder.
    func finish(with failure: PayabliGenericError) {
        finished.failure = failure
    }

    /// The token held now, without calling the provider.
    ///
    /// - Returns: the token held, or `nil` when none is held, a mint is in flight, or this holder is finished.
    func heldToken() -> String? {
        guard inFlightMint == nil, terminalFailure == nil else { return nil }
        return currentToken
    }

    /// Reports `rejectedToken` as refused and returns the token to use instead.
    /// Callers invoke this after receiving HTTP 401, then retry once.
    /// An in-flight mint is joined before the already-rotated check, because the token held may itself be the one just refused.
    ///
    /// - Parameter rejectedToken: the token the 401 named, so a late rejection reuses the rotation instead of minting over it.
    /// - Returns: the token to send instead, joined from an in-flight mint when one is under way.
    func invalidateAndRefresh(rejectedToken: String) async throws -> String {
        if let mintID = inFlightMintID, RefreshInProgress.carries(self, refresh: mintID) {
            guard let held = currentToken else {
                logger.error("The token provider requested a token before returning its first one")
                throw refuseReentry(into: mintID)
            }
            return held
        }

        if let failure = terminalFailure {
            throw failure
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

    /// Keeps `token` as refused by a pinned route, when it is still the token held.
    ///
    /// - Parameter token: the credential the pinned request carried.
    func recordPinnedRefusal(of token: String) {
        if token == currentToken {
            pinnedRefusal = token
        }
    }

    /// Replaces the token a pinned route refused, through the same shared refresh a rejection takes.
    ///
    /// A token that has rotated since the refusal is kept, and a renewal that starts while another runs joins it.
    ///
    /// - Returns: whether a refusal was waiting to be renewed; false asks the provider for nothing.
    /// - Throws: the provider's failure, as a refresh raises it.
    func renewPinnedRefusal() async throws -> Bool {
        guard let refused = pinnedRefusal else { return false }
        _ = try await invalidateAndRefresh(rejectedToken: refused)
        if pinnedRefusal == refused {
            pinnedRefusal = nil
        }
        return true
    }

    /// Calls the provider, checks what it returned, and installs it, with one call shared between
    /// every caller waiting on it.
    /// The check and the install are inside the task, so a joiner resumes only with a token already installed.
    ///
    /// - Parameter rejectedToken: the token a rejection named, nil on the first mint, and what `check` refuses a repeat of.
    /// - Returns: the minted token, checked and installed, shared with every caller that joined.
    private func mint(replacing rejectedToken: String?) async throws -> String {
        let provider = config.tokenProvider
        let mintID = UUID()
        let clock = self.clock
        let task = Task<String, Error> { [logger] in
            logger.info("Requesting an access token from the partner tokenProvider")
            let startedAt = ContinuousClock.now
            let minted: String
            do {
                minted = try await Self.racedMint(holder: self, mintID: mintID, provider: provider, clock: clock)
            } catch is ProviderTimedOut {
                // Named apart from every other provider throw below: a caller can tell a slow broker
                // from a rejected credential or a thrown error, which is the whole point of the bound.
                logger.error("The token provider did not return within the deadline")
                self.reportFailure(.timedOut, since: startedAt)
                throw PayabliGenericError(
                    type: .tokenProviderFailed,
                    reason: "Token request failed",
                    detail: "The tokenProvider did not return within \(Int(Self.providerTimeout)) seconds."
                )
            } catch {
                // Any throw from the provider is host code, this SDK's own error type included. The detail is
                // fixed because a host's error can carry request data; its type name still reaches a caller
                // through `underlying` via `RedactedCause`.
                logger.error("The token provider failed")
                if await self.raisedReentryRefusal(error, into: mintID) {
                    self.reportFailure(.reentered, since: startedAt)
                } else {
                    self.reportFailure(.threw, thrown: error, since: startedAt)
                }
                throw PayabliGenericError(
                    type: .tokenProviderFailed,
                    reason: "Token request failed",
                    detail: "The tokenProvider threw an error.",
                    underlying: RedactedCause(error)
                )
            }
            if let refusal = Self.refusal(of: minted, replacing: rejectedToken) {
                logger.error("The minted token was refused before it was committed")
                self.reportFailure(refusal.reason, since: startedAt)
                throw refusal.error
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

    /// The ceiling on one call to the host's `tokenProvider`.
    private static let providerTimeout: TimeInterval = 30

    /// Distinguishes a provider that never returned from anything it threw, so `mint(replacing:)` can
    /// raise a reason naming the timeout rather than folding it into "the provider failed".
    private struct ProviderTimedOut: Error {}

    /// A value only the first of two racing sides sets. `racedMint` uses it to keep whichever side
    /// loses from resuming a continuation the other has already resumed.
    private final class DecidedOnce: @unchecked Sendable {
        private let lock = NSLock()
        private var fired = false

        /// True the first call, false every call after.
        ///
        /// - Returns: whether this is the first claim, so only one of two racing sides takes it.
        func claim() -> Bool {
            lock.lock()
            defer { lock.unlock() }
            if fired {
                return false
            }
            fired = true
            return true
        }
    }

    /// Races `provider` against `clock`'s deadline through a continuation, not a `TaskGroup`, which would wait
    /// on a provider that ignores cancellation. The loser runs on unawaited; `decided` stops it resuming.
    /// A provider blocking a thread outside a suspension point isn't bounded by this.
    ///
    /// - Parameter holder: the auth whose provider call this is, named in the mark `withMark` records.
    /// - Parameter mintID: the id naming this mint, which the mark carries so a stale task cannot answer for it.
    /// - Parameter provider: the host's `tokenProvider`, the side that returns the token.
    /// - Parameter clock: what the deadline is waited on, `expire(after:)` bounding the call.
    /// - Returns: the token the provider returned before the deadline passed.
    private static func racedMint(
        holder: PayabliAuth,
        mintID: UUID,
        provider: @escaping PayabliTokenRefresh,
        clock: any RetryClock
    ) async throws -> String {
        let decided = DecidedOnce()
        return try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<String, Error>) in
            let providerTask = Task {
                do {
                    let token = try await RefreshInProgress.withMark(holder: holder, refresh: mintID) {
                        try await provider()
                    }
                    guard decided.claim() else { return }
                    continuation.resume(returning: token)
                } catch {
                    guard decided.claim() else { return }
                    continuation.resume(throwing: error)
                }
            }
            Task {
                try? await clock.expire(after: Self.providerTimeout)
                guard decided.claim() else { return }
                providerTask.cancel()
                continuation.resume(throwing: ProviderTimedOut())
            }
        }
    }

    /// Waits for a mint already under way and answers with what it produced, unless this caller was
    /// cancelled while waiting.
    /// The mint runs on for its other waiters, and this caller's cancellation is raised, not answered past.
    ///
    /// - Parameter mint: the in-flight mint, awaited by result so its failure does not throw past the cancellation check.
    /// - Returns: the token the mint produced.
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
    ///
    /// - Parameter mintID: the id of the mint whose mark this is; a later mint's mark is left alone.
    private func releaseMint(_ mintID: UUID) {
        if reentryRefusal?.mintID == mintID {
            reentryRefusal = nil
        }
        guard inFlightMintID == mintID else { return }
        inFlightMint = nil
        inFlightMintID = nil
    }

    /// Installs the minted token. Called only once the token has passed `check(_:replacing:)`, so
    /// nothing here can install one that was refused.
    ///
    /// - Parameter fresh: the token the provider returned, already passed `check(_:replacing:)`.
    /// - Parameter mintID: the id naming the mint that produced it, dropped from the in-flight mark here.
    private func commit(_ fresh: String, mintID: UUID) {
        currentToken = fresh
        releaseMint(mintID)
        logger.info("Access token installed")
    }

    /// Why a minted token may not be committed, or `nil` when it may. Every token this holder installs passes here, so
    /// nothing downstream re-checks one. A blank one goes out unauthenticated, and a repeat of the refused one costs a
    /// provider call per 401 with no end.
    ///
    /// - Parameter fresh: the token the provider returned, refused when blank, unsafe as a header value, or a repeat of the refusal.
    /// - Parameter rejectedToken: the token a rejection named; a mint equal to it is refused rather than installed.
    /// - Returns: the refusal's reported reason and the error a caller receives, or `nil` for a token that may be installed.
    private static func refusal(
        of fresh: String,
        replacing rejectedToken: String?
    ) -> (reason: TokenFailureReason, error: PayabliGenericError)? {
        let refused: (TokenFailureReason, String)? = if fresh.isBlank {
            (.blankToken, "The tokenProvider returned a blank token.")
        } else if !fresh.isHeaderSafe {
            (.unusableToken, "The tokenProvider returned a token that cannot be an HTTP header value.")
        } else if fresh == rejectedToken {
            (.unchangedToken, "The tokenProvider returned the token the server rejected.")
        } else {
            nil
        }
        guard let (reason, detail) = refused else { return nil }
        return (reason, PayabliGenericError(type: .tokenProviderFailed, reason: "Token request failed", detail: detail))
    }

    /// Builds the refusal of a read made from inside the provider call `mintID` runs, and keeps it for that call.
    ///
    /// - Parameter mintID: the provider call the read came from.
    /// - Returns: the refusal to throw.
    private func refuseReentry(into mintID: UUID) -> PayabliGenericError {
        let refusal = PayabliGenericError(
            type: .tokenProviderFailed,
            reason: "Access token unavailable",
            detail: "The tokenProvider made a request that needs the token it was asked to supply."
        )
        reentryRefusal = (mintID, refusal)
        return refusal
    }

    /// Whether the provider call `mintID` threw back the refusal this holder raised into it, rather than an error of
    /// its own.
    ///
    /// - Parameter error: what the provider threw.
    /// - Parameter mintID: the provider call that threw it.
    /// - Returns: true only when `error` matches that refusal in every field and wraps nothing.
    private func raisedReentryRefusal(_ error: Error, into mintID: UUID) -> Bool {
        guard let raised = reentryRefusal, raised.mintID == mintID,
              let thrown = error as? PayabliGenericError else { return false }
        let refusal = raised.error
        return thrown.underlying == nil && thrown.type == refusal.type && thrown.reason == refusal.reason
            && thrown.detail == refusal.detail && thrown.httpStatus == refusal.httpStatus && thrown.rawCode == refusal.rawCode
    }

    /// Records `auth.tokenFailed` for the provider call this mint ran. Callers that joined the mint record nothing.
    ///
    /// - Parameter reason: which of the six refusals it was.
    /// - Parameter thrown: what the provider threw, named as `failure_type`, only when `reason` is `threw`.
    /// - Parameter startedAt: when the provider was called.
    private nonisolated func reportFailure(_ reason: TokenFailureReason, thrown: Error? = nil, since startedAt: ContinuousClock.Instant) {
        let (seconds, attoseconds) = (ContinuousClock.now - startedAt).components
        // A token failure waits for its batch instead of forcing a send.
        TelemetryRecorders.record(
            TelemetryEventName.authTokenFailed,
            properties: Self.failureProperties(reason, thrown: thrown, milliseconds: seconds * 1000 + attoseconds / 1_000_000_000_000_000),
            waitsForBatch: true
        )
    }

    /// The properties `auth.tokenFailed` carries.
    ///
    /// - Parameter reason: which of the six refusals it was.
    /// - Parameter thrown: what the provider threw, named as `failure_type`; `nil` for every reason but `threw`.
    /// - Parameter milliseconds: how long the provider call took.
    /// - Returns: the event's properties.
    private static func failureProperties(
        _ reason: TokenFailureReason,
        thrown: Error?,
        milliseconds: Int64
    ) -> [String: String] {
        var properties = [
            TelemetryProperty.outcome.rawValue: "failed",
            TelemetryProperty.reason.rawValue: reason.rawValue,
            TelemetryProperty.durationMs.rawValue: String(milliseconds)
        ]
        if let thrown {
            properties[TelemetryProperty.failureType.rawValue] = RedactedCause(thrown).simpleTypeName
        }
        return properties
    }

    /// Drops the held token and any call in flight, and revives a finished holder, so the next read mints again.
    func reset() {
        currentToken = nil
        inFlightMint = nil
        inFlightMintID = nil
        pinnedRefusal = nil
        finished.failure = nil
    }
}

/// The failure that finished a holder, behind a lock so it can be read from outside the actor.
private final class FinishedSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: PayabliGenericError?

    var failure: PayabliGenericError? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Why a provider call did not produce a token the holder could install, as `auth.tokenFailed` names it.
enum TokenFailureReason: String {
    case threw
    case timedOut
    case blankToken
    case unusableToken
    case unchangedToken
    case reentered
}

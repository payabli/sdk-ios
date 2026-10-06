import Foundation
import PayabliSDKCore

// MARK: - Initialize & reinitialize (PRD §19.1)

@MainActor
extension PayabliTTP {
    // MARK: - Public entrypoints

    /// One-call startup:
    ///   0. Eligibility gate (FR-11J.2).
    ///   1. Attestation — cold path runs `/challenge` → `/register` → `/attest`;
    ///      warm path re-uses the keychain-cached `deviceId`.
    ///   2. `GET /config/{entry}` (attestation-gated).
    ///   3. Hand credentials to the provider (NFR-5D — runtime only).
    ///   4. Prepare reader, transition to `.ready`.
    public func initialize() async throws {
        try await reportingToHost(.initialize) {
            try await runSessionSetup(.initialize) { try await self.runInitialize() }
        }
    }

    /// Serialises the operations that move the session's state. A caller of the same kind joins the one
    /// in flight; a caller of another kind waits for it and then runs its own.
    func runSessionSetup(
        _ kind: SessionSetupKind,
        _ work: @escaping @MainActor () async throws -> Void
    ) async throws {
        if let existing = inFlightSessionSetup, existing.kind == kind {
            return try await existing.task.value
        }

        // Chains behind an operation of the other kind. Re-checking in a loop
        // re-awaits a task that has already finished and spins the main actor
        // until the slot is cleared, starving everything else on it.
        let previous = inFlightSessionSetup?.task
        let id = nextSessionSetupID
        nextSessionSetupID += 1

        let task = Task<Void, Error> { @MainActor in
            // Its failure belongs to its own caller.
            if let previous {
                _ = try? await previous.value
            }
            try await work()
        }
        inFlightSessionSetup = (kind, task, id)
        defer {
            if inFlightSessionSetup?.id == id {
                inFlightSessionSetup = nil
            }
        }
        try await task.value
    }

    private func runInitialize() async throws {
        // 0. Eligibility.
        try await runEligibility()

        // Start from `.idle`, whatever the caller left behind. The matrix is
        // narrow — from `.sessionExpired` only `.reinitializing` is reachable —
        // and transition results are discarded, so without this every phase ran
        // and the state never moved.
        sessionManager.reset()
        syncPublished()

        // 1. Attestation (cold) or warm deviceId. The session reaches
        //    `.fetchingConfig` on success.
        try await runAttestationPhase()

        // 2. Fetch /config.
        let config = try await runFetchConfigPhase()
        multicaster.emit(.configReceived)

        // 3. Configure provider.
        try runConfigurePhase(credentials: config.providerCredentials)

        // 4. Prepare reader and mark ready.
        try await runPrepareReaderPhase()
        _ = sessionManager.transition(to: .ready)
        syncPublished()
        multicaster.emit(.readerReady)
    }

    /// `@objc` companion to `initialize()` for ObjC / MAUI / Flutter / RN
    /// consumers. Bridges the `async throws` Swift method to a callback-based
    /// signature: `completion(nil)` on success, `completion(NSError)` on
    /// failure, a ``TapToPayError`` with its catalog number as the code.
    ///
    /// The completion handler is always invoked on the main thread because
    /// the entire `PayabliTTP` surface is `@MainActor`.
    @objc public func initialize(completion: @escaping (NSError?) -> Void) {
        Task { @MainActor in
            do {
                try await self.initialize()
                completion(nil)
            } catch {
                completion(error.toPayabliNSError())
            }
        }
    }

    /// Session refresh for host/bridge re-entry.
    ///
    /// No-op when already `.ready`. For non-terminal transient states
    /// (`.sessionExpired`, `.idle`, `.error`) re-runs steps 2–4 of
    /// `initialize()`. NFR-5D forbids providers from caching credentials
    /// across sessions, so every refresh re-fetches `/config`.
    public func reinitializeIfNeeded() async throws {
        try await reportingToHost(.reinitialize) { try await reinitialize() }
    }

    func reinitialize() async throws {
        try await runSessionSetup(.reinitialize) { try await self.runReinitializeIfNeeded() }
    }

    private func runReinitializeIfNeeded() async throws {
        switch sessionState {
        case .ready:
            return
        case .sessionExpired, .idle, .failed:
            break
        default:
            throw PayabliTTPError.notReady(current: sessionState)
        }

        multicaster.emit(.reinitializeStarted)
        _ = sessionManager.transition(to: .reinitializing)
        syncPublished()
        _ = sessionManager.transition(to: .fetchingConfig)
        syncPublished()

        // 2. Fresh /config (credentials never survive between sessions).
        let config = try await runFetchConfigPhase()
        multicaster.emit(.configReceived)

        // 3. Re-configure provider.
        try runConfigurePhase(credentials: config.providerCredentials)

        // 4. Re-prepare reader and mark ready.
        try await runPrepareReaderPhase()
        _ = sessionManager.transition(to: .ready)
        syncPublished()
        multicaster.emit(.reinitializeCompleted)
    }

    /// `@objc` companion to `reinitializeIfNeeded()`. Same callback contract
    /// as the `initialize` companion above — always invoked on the main
    /// thread.
    @objc public func reinitializeIfNeeded(
        completion: @escaping (NSError?) -> Void
    ) {
        Task { @MainActor in
            do {
                try await self.reinitializeIfNeeded()
                completion(nil)
            } catch {
                completion(error.toPayabliNSError())
            }
        }
    }

    // MARK: - Phase 0 — eligibility

    private func runEligibility() async throws {
        guard case let .failure(err) = await provider.checkEligibility() else { return }
        markError(err)
        syncPublished()
        throw err
    }

    // MARK: - Phase 1 — attestation (cold) or warm start

    /// On success leaves the session in `.fetchingConfig`.
    /// `.devicePendingActivation` maps to `.pendingActivation`.
    ///
    /// Returns nothing: the handle worth keeping is the one the config call's
    /// assertion is signed for, which this phase cannot know.
    private func runAttestationPhase() async throws {
        do {
            // Inside the handling below, because reading the binding can fail and a
            // failure that skipped it would throw out of `initialize()` while the
            // published state stayed where `reset()` left it, and emit nothing. The
            // caller and the observable state would then describe different things.
            if try await attestation.isAttested(for: entryPoint) {
                _ = sessionManager.transition(to: .fetchingConfig)
                syncPublished()
                return
            }

            _ = sessionManager.transition(to: .attestingDevice)
            syncPublished()
            multicaster.emit(.attestationStarted)

            _ = try await attestation.attest(entry: entryPoint)
            multicaster.emit(.attestationCompleted)
            _ = sessionManager.transition(to: .fetchingConfig)
            syncPublished()
        } catch PayabliTTPError.devicePendingActivation {
            if let failure = landPendingActivation() {
                multicaster.emit(.attestationFailed(error: ErrorSummary.of(failure)))
                throw failure
            }
            throw PayabliTTPError.devicePendingActivation
        } catch {
            markError(error)
            syncPublished()
            multicaster.emit(.attestationFailed(error: ErrorSummary.of(error)))
            throw error
        }
    }

    // MARK: - Phase 2 — fetch /config

    /// Pre: session is in `.fetchingConfig`. Error handling:
    ///   - backend says pending → `.pendingActivation`
    ///   - 401, either a refused binding or a refused bearer → rewrap as
    ///     `.configFailed`, relaying the reason. Dropping a binding is the config
    ///     call's, which knows which of the two it is holding
    ///   - anything else → rewrapped as `.configFailed` so the domain and code
    ///     stay what the bridges read, keeping the parsed reason
    ///
    /// The state is classified from the failure as it arrived, not from the
    /// wrapper: the error names which phase failed, the state names the remedy.
    private func runFetchConfigPhase() async throws -> TTPConfig {
        do {
            return try await configClient.fetchConfig(entry: entryPoint)
        } catch let pending as ConfigPendingActivation {
            if let failure = landPendingActivation(answeredFor: pending.presentedDeviceId) {
                multicaster.emit(.configFailed(error: ErrorSummary.of(failure)))
                throw failure
            }
            throw PayabliTTPError.devicePendingActivation
        } catch let err as PayabliGenericError where err.type == .tokenExpired {
            // Two failures arrive as `.tokenExpired` here: the service refusing the
            // binding the request presented, and the transport refusing the bearer
            // after its retry. The first is dropped by the config call, which knows
            // which handle it presented; the second is about a token and drops
            // nothing. The reason is relayed either way, so it names which happened
            // instead of this layer claiming an outcome for both.
            let failure = PayabliTTPError.configFailed(reason: "Config rejected (401): \(err.reason)")
            markError(err)
            syncPublished()
            multicaster.emit(.configFailed(error: ErrorSummary.of(failure)))
            throw failure
        } catch {
            // Wrapped, so a host receives every configuration failure under the
            // `configFailed` case's catalog entry.
            //
            // The reason is the error's own parsed description, so the fields the
            // service named still reach the merchant. `String(describing:)` renders
            // every stored property instead, the page token among them.
            let failure = error as? PayabliTTPError
                ?? PayabliTTPError.configFailed(reason: error.localizedDescription)
            // Marked as it arrived, so a permission this paypoint has not
            // granted still reaches `.pendingActivation` and a service that was
            // briefly away still reads as one to try again.
            markError(error)
            syncPublished()
            multicaster.emit(.configFailed(error: ErrorSummary.of(failure)))
            throw failure
        }
    }

    // MARK: - Phase 3 — configure provider

    /// Hands the opaque `credentials` dict to the adapter. Provider-specific
    /// parsing never leaks into the facade.
    private func runConfigurePhase(credentials: [String: String]) throws {
        do {
            try provider.configure(credentials: credentials)
        } catch {
            markError(error)
            syncPublished()
            throw error as? PayabliTTPError
                ?? PayabliTTPError.readerSetupFailed(reason: String(describing: error))
        }
    }

    // MARK: - Phase 4 — prepare reader

    private func runPrepareReaderPhase() async throws {
        // Progress belongs to one configuration. The handler below carries which
        // one it is, and this releases the claim when the configuration ends, so
        // a percentage raised afterwards is dropped rather than announced.
        nextConfigurationID += 1
        let configuration = nextConfigurationID
        activeConfiguration = configuration
        defer {
            if activeConfiguration == configuration {
                activeConfiguration = nil
            }
        }

        _ = sessionManager.transition(to: .initializingReader(percent: nil))
        syncPublished()
        multicaster.emit(.readerInitializing)
        do {
            try await provider.prepareReader { [weak self] event in
                self?.handleReaderEvent(event, from: configuration)
            }
            readerSessionGeneration += 1
        } catch PayabliTTPError.termsNotAccepted {
            // Not an error state: the session is waiting on a person, the way it waits on one in
            // `pendingActivation`. The host presents the terms and initializes again, and the reader
            // stays up meanwhile because it is what presents them.
            markPendingTerms()
            throw PayabliTTPError.termsNotAccepted
        } catch {
            markError(error)
            syncPublished()
            throw error as? PayabliTTPError
                ?? PayabliTTPError.readerSetupFailed(reason: String(describing: error))
        }
    }

    // MARK: - Shared transitions

    private func landPendingActivation(answeredFor presented: String? = nil) -> Error? {
        let failure: Error
        switch storedRegistration() {
        case let .held(activationId) where presented == nil || presented == activationId:
            _ = sessionManager.transition(to: .pendingActivation(activationId: activationId))
            syncPublished()
            multicaster.emit(.devicePendingActivation)
            return nil
        case .held, .none where presented != nil:
            let stale = PayabliTTPError.configFailed(
                reason: "The registration changed while the configuration was fetched; initialize again"
            )
            _ = sessionManager.transition(to: .failed(reason: .serviceUnavailable))
            syncPublished()
            return stale
        case .none:
            failure = PayabliTTPError.configFailed(reason: "The device is pending activation, and no registration is stored for it")
        case .unreadable:
            failure = TapToPayError(
                type: .deviceKeyUnavailable,
                reason: "The stored registration could not be read",
                detail: nil
            )
        }
        sessionManager.markError(failure, registration: .none)
        syncPublished()
        return failure
    }

    func markError(_ error: Error) {
        sessionManager.markError(error, registration: storedRegistration())
    }

    private func storedRegistration() -> StoredRegistration {
        do {
            return try attestation.cachedDeviceId(for: entryPoint).map { .held(activationId: $0) } ?? .none
        } catch {
            return .unreadable
        }
    }

    private func markPendingTerms() {
        _ = sessionManager.transition(to: .pendingTerms)
        syncPublished()
        multicaster.emit(.termsRequired)
    }
}

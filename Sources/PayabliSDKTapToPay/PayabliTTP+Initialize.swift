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
        try await runSessionSetup(.initialize) { try await self.runInitialize() }
    }

    /// Serialises the two entry points that build a session.
    ///
    /// Both reset or advance the same state and both configure and prepare the
    /// same provider, so overlapping them lets one finish against the other's
    /// session and report success on transitions that were rejected. A caller of
    /// the same kind joins the operation in flight; a caller of the other kind
    /// waits for it and then runs its own, which keeps their meanings distinct:
    /// re-initializing skips attestation, initializing does not.
    private func runSessionSetup(
        _ kind: SessionSetupKind,
        _ work: @escaping @MainActor () async throws -> Void
    ) async throws {
        if let existing = inFlightSessionSetup, existing.kind == kind {
            return try await existing.task.value
        }

        // Chain behind an operation of the other kind rather than polling for
        // it. Re-checking in a loop re-awaits a task that has already finished
        // and spins the main actor until the slot is cleared, which starves
        // everything else running on it.
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
        let deviceId = try await runAttestationPhase()

        // 2. Fetch /config.
        let config = try await runFetchConfigPhase()
        cachedDeviceId = deviceId
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
    /// failure (domain `"com.payabli.ttp"` for typed `PayabliTTPError`s).
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
        try await runSessionSetup(.reinitialize) { try await self.runReinitializeIfNeeded() }
    }

    private func runReinitializeIfNeeded() async throws {
        switch sessionState {
        case .ready:
            return
        case .sessionExpired, .idle, .error:
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
        sessionManager.markError(err)
        syncPublished()
        throw err
    }

    // MARK: - Phase 1 — attestation (cold) or warm start

    /// Returns the `deviceId` to cache. On success leaves the session in
    /// `.fetchingConfig`. `.devicePendingActivation` maps to `.pendingActivation`.
    private func runAttestationPhase() async throws -> String? {
        if attestation.isAlreadyAttested {
            _ = sessionManager.transition(to: .fetchingConfig)
            syncPublished()
            return attestation.cachedDeviceId
        }

        _ = sessionManager.transition(to: .attestingDevice)
        syncPublished()
        multicaster.emit(.attestationStarted)

        do {
            let result = try await attestation.attest(entry: entryPoint, appId: appId)
            multicaster.emit(.attestationCompleted)
            _ = sessionManager.transition(to: .fetchingConfig)
            syncPublished()
            return result.deviceId
        } catch PayabliTTPError.devicePendingActivation {
            markPendingActivation()
            throw PayabliTTPError.devicePendingActivation
        } catch {
            sessionManager.markError(error)
            syncPublished()
            multicaster.emit(.attestationFailed(error: String(describing: error)))
            throw error
        }
    }

    // MARK: - Phase 2 — fetch /config

    /// Pre: session is in `.fetchingConfig`. Error handling:
    ///   - backend says pending → `.pendingActivation`
    ///   - 401 (stale assertion) → clear attestation cache, rewrap as `.configFailed`
    ///   - anything else → `.error`, rewrap non-typed errors as `.configFailed`
    private func runFetchConfigPhase() async throws -> TTPConfig {
        do {
            return try await configClient.fetchConfig(entry: entryPoint)
        } catch PayabliTTPError.devicePendingActivation {
            markPendingActivation()
            throw PayabliTTPError.devicePendingActivation
        } catch let err as PayabliGenericError where err.code == .tokenExpired {
            attestation.clearCache()
            sessionManager.markError(err)
            syncPublished()
            let failure = PayabliTTPError.configFailed(reason: "Config rejected (401) — attestation cleared")
            multicaster.emit(.configFailed(error: String(describing: failure)))
            throw failure
        } catch {
            sessionManager.markError(error)
            syncPublished()
            let failure = error as? PayabliTTPError
                ?? PayabliTTPError.configFailed(reason: String(describing: error))
            multicaster.emit(.configFailed(error: String(describing: failure)))
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
            sessionManager.markError(error)
            syncPublished()
            throw error as? PayabliTTPError
                ?? PayabliTTPError.readerSetupFailed(reason: String(describing: error))
        }
    }

    // MARK: - Phase 4 — prepare reader

    private func runPrepareReaderPhase() async throws {
        _ = sessionManager.transition(to: .initializingReader)
        syncPublished()
        multicaster.emit(.readerInitializing)
        do {
            try await provider.prepareReader()
            readerSessionGeneration += 1
        } catch {
            sessionManager.markError(error)
            syncPublished()
            throw error as? PayabliTTPError
                ?? PayabliTTPError.readerSetupFailed(reason: String(describing: error))
        }
    }

    // MARK: - Shared transitions

    private func markPendingActivation() {
        _ = sessionManager.transition(to: .pendingActivation)
        syncPublished()
        multicaster.emit(.devicePendingActivation)
    }
}

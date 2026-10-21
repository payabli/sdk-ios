import Foundation
import PayabliSDKCore

// MARK: - Initialize & reinitialize

@available(iOS 16.7, *)
@MainActor
extension PayabliTTP {
    // MARK: - Public entrypoints

    /// One-call startup:
    ///   0. Eligibility gate.
    ///   1. Attestation — cold path runs `/challenge` → `/register` → `/attest`;
    ///      warm path re-uses the keychain-cached `deviceId`.
    ///   2. `GET /config/{entry}` (attestation-gated).
    ///   3. Hand credentials to the provider, which holds them at runtime only.
    ///   4. Prepare reader, transition to `.ready`.
    ///
    /// A call made during a charge waits for the charge to end, then runs.
    public func initialize() async throws {
        try await reportingToHost {
            try await runSessionSetup(.initialize) { try await self.runInitialize() }
        }
    }

    /// Runs a session setup through the process's gate.
    ///
    /// - Parameters:
    ///   - kind: Which setup this is; this `PayabliTTP`'s next call of an equal kind joins it until a charge claims
    ///     the gate.
    ///   - work: The setup, run once every operation already in the gate has finished.
    func runSessionSetup(
        _ kind: SessionSetupKind,
        _ work: @escaping @MainActor () async throws -> Void
    ) async throws {
        try await SessionSetupGate.shared.run(kind, for: ObjectIdentifier(self), work)
    }

    /// Holds the process's gate for a charge. A setup call made meanwhile, on any `PayabliTTP`, waits until `body`
    /// returns.
    ///
    /// - Parameter body: The charge, run in the caller's task while the gate is held.
    /// - Returns: The charge's result.
    /// - Throws: `notReady` when a charge already holds the gate, whether it is running or still waiting
    ///   for a setup to finish.
    func holdingSessionSetup<T>(_ body: @MainActor () async throws -> T) async throws -> T {
        let gate = SessionSetupGate.shared
        if gate.isHeldByCharge {
            throw PayabliTTPError.notReady(current: sessionState)
        }
        return try await gate.holdForCharge(body)
    }

    /// Runs once per setup, by its owner: a caller that joins it adds no report.
    private func runInitialize() async throws {
        let clock = ContinuousClock()
        let start = clock.now
        reports.initializeStarted()
        do {
            try await runInitializePhases()
        } catch let withdrawn as CancellationError {
            throw withdrawn
        } catch {
            reports.initializeEnded(error, after: clock.now - start)
            throw error
        }
        reports.initializeSucceeded(after: clock.now - start)
    }

    private func runInitializePhases() async throws {
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

        // 3. Configure provider.
        try runConfigurePhase(credentials: config.providerCredentials)

        // 4. Prepare reader and mark ready.
        try await runPrepareReaderPhase()
        _ = sessionManager.transition(to: .ready)
        syncPublished()
    }

    /// `@objc` companion to `initialize()` for ObjC / MAUI / Flutter / RN
    /// consumers. Bridges the `async throws` Swift method to a callback-based
    /// signature: `completion(nil)` on success, `completion(NSError)` on
    /// failure, a ``TapToPayError`` with its catalog number as the code.
    ///
    /// The completion handler is always invoked on the main thread because
    /// the entire `PayabliTTP` surface is `@MainActor`.
    ///
    /// - Parameter completion: the error the initialization failed with, or `nil` when it succeeded.
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

    /// The repair `charge` runs first: nothing when `.ready`, and steps 2–4 of `initialize()` from
    /// `.sessionExpired`, `.idle` or `.failed`, with a fresh `/config` each time.
    func reinitialize() async throws {
        try await runSessionSetup(.reinitialize) { try await self.runReinitializeIfNeeded() }
    }

    func runReinitializeIfNeeded() async throws {
        switch sessionState {
        case .ready:
            return
        case .sessionExpired, .idle, .failed:
            break
        default:
            throw PayabliTTPError.notReady(current: sessionState)
        }

        _ = sessionManager.transition(to: .reinitializing)
        syncPublished()
        _ = sessionManager.transition(to: .fetchingConfig)
        syncPublished()

        // 2. Fresh /config (credentials never survive between sessions).
        let config = try await runFetchConfigPhase()

        // 3. Re-configure provider.
        try runConfigurePhase(credentials: config.providerCredentials)

        // 4. Re-prepare reader and mark ready.
        try await runPrepareReaderPhase()
        _ = sessionManager.transition(to: .ready)
        syncPublished()
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
            // published state stayed where `reset()` left it. The
            // caller and the observable state would then describe different things.
            if try await attestation.isAttested(for: entryPoint) {
                _ = sessionManager.transition(to: .fetchingConfig)
                syncPublished()
                return
            }

            _ = sessionManager.transition(to: .attestingDevice)
            syncPublished()

            _ = try await attestation.attest(entry: entryPoint)
            _ = sessionManager.transition(to: .fetchingConfig)
            syncPublished()
        } catch PayabliTTPError.devicePendingActivation {
            if let failure = landPendingActivation() {
                throw failure
            }
            throw PayabliTTPError.devicePendingActivation
        } catch {
            markError(error)
            syncPublished()
            throw error
        }
    }

    // MARK: - Phase 2 — fetch /config

    /// Fetches `/config`, with the session in `.fetchingConfig`.
    ///
    /// A pending backend lands `.pendingActivation`; a core error, a 401 included, passes through as it
    /// arrived; anything else wraps as `.configFailed`, with the state classified from the arrival.
    ///
    /// - Returns: the route's configuration, carrying the reader credentials.
    private func runFetchConfigPhase() async throws -> TTPConfig {
        do {
            return try await configClient.fetchConfig(entry: entryPoint)
        } catch let pending as ConfigPendingActivation {
            if let failure = landPendingActivation(answeredFor: pending.presentedDeviceId) {
                throw failure
            }
            throw PayabliTTPError.devicePendingActivation
        } catch {
            // A core error keeps its own code and the wait the service asked for, and a cancellation stays one.
            // Anything else is wrapped with its parsed description, so the fields
            // the service named still reach the merchant. `String(describing:)`
            // renders every stored property instead, the page token among them.
            let failure: Error = if error is PayabliTTPError || error is any PayabliError || error is CancellationError {
                error
            } else {
                PayabliTTPError.configFailed(reason: error.localizedDescription)
            }
            // Marked as it arrived, so a permission this paypoint has not
            // granted still reaches `.pendingActivation` and a service that was
            // briefly away still reads as one to try again.
            markError(error)
            syncPublished()
            throw failure
        }
    }

    // MARK: - Phase 3 — configure provider

    /// Hands the opaque `credentials` dict to the adapter. Provider-specific
    /// parsing never leaks into the facade.
    ///
    /// - Parameter credentials: the `providerCredentials` dict `/config` answered with, opaque to the facade.
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
        // a percentage raised afterwards is dropped.
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
        do {
            try await provider.prepareReader { [weak self] event in
                self?.handleReaderEvent(event, from: configuration)
            }
            SessionSetupGate.shared.readerGeneration += 1
            preparedReader = configuration
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
    }
}

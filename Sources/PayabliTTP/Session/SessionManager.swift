import Foundation

/// Orchestrates the full SDK initialization lifecycle using Ports (protocols).
/// Coordinates: attestation → config fetch → card reader setup.
/// Emits domain events at each step and enforces state machine transitions.
///
/// Dependencies are injected as protocols for testability:
/// - DeviceAttesting (App Attest / mock)
/// - Networking via AttestationService
/// - CardReading (Fiserv / mock)
final class SessionManager {

    // MARK: - State

    private(set) var state: SessionState = .idle

    /// Fiserv config held in memory only (ephemeral credentials).
    private(set) var currentConfig: ConfigResponse?

    // MARK: - Ports (injected)

    private let attester: DeviceAttesting
    private let attestationService: AttestationService
    private let transactionService: TransactionService
    private let cardReader: CardReading
    private let deviceId: String
    private let events: EventStream

    init(
        attester: DeviceAttesting,
        attestationService: AttestationService,
        transactionService: TransactionService,
        cardReader: CardReading,
        deviceId: String,
        events: EventStream
    ) {
        self.attester = attester
        self.attestationService = attestationService
        self.transactionService = transactionService
        self.cardReader = cardReader
        self.deviceId = deviceId
        self.events = events
    }

    // MARK: - Full initialization (called by PayabliTTP.initialize())

    /// Runs the complete 3-phase initialization:
    /// Phase A: Device attestation (one-time, skipped if already attested)
    /// Phase B: Fetch Fiserv config from backend
    /// Phase C: Initialize card reader for NFC
    func initialize() async throws {
        do {
            // Phase A: Attestation
            try transition(to: .attestingDevice)
            events.emit(.attestationStarted)

            try await performAttestationIfNeeded()

            events.emit(.attestationCompleted)

            // Phase B: Fetch config
            try transition(to: .fetchingConfig)

            let config = try await fetchConfig()
            currentConfig = config
            transactionService.configure(requestToken: config.requestToken)

            events.emit(.configFetched)

            // Phase C: Card reader
            try transition(to: .initializingReader)
            events.emit(.readerInitializing)

            try await setupCardReader(with: config)

            try transition(to: .ready)
            events.emit(.sessionReady)
        } catch {
            // Ensure internal state is .error so recovery via reinitializeIfNeeded() works.
            state = .error(error.localizedDescription)
            throw error
        }
    }

    // MARK: - Reinitialize (session recovery)

    /// Re-establishes the NFC session if it has expired.
    /// Skips attestation (already done), re-fetches config (credentials may have rotated),
    /// and re-initializes the card reader.
    /// Called automatically by charge() or proactively by partners.
    func reinitializeIfNeeded() async throws {
        switch state {
        case .idle:
            try await initialize()
            return
        case .error:
            // Reset to idle via the state machine before re-running full init.
            try transition(to: .idle)
            try await initialize()
            return
        case .ready:
            guard !cardReader.isSessionActive else { return }
            try transition(to: .sessionExpired)
            events.emit(.sessionExpired)
        case .sessionExpired:
            // Already marked expired — proceed directly to reinit.
            break
        default:
            // Initialization is in progress on another call; the caller should
            // await the current initialize() or retry after it completes.
            throw PayabliTTPError.invalidState(
                "SDK initialization is in progress. Await initialize() before calling reinitializeIfNeeded()."
            )
        }

        // At this point state is .sessionExpired.
        do {
            try transition(to: .reinitializing)
            events.emit(.reinitializationStarted)

            let config = try await fetchConfig()
            currentConfig = config
            transactionService.configure(requestToken: config.requestToken)

            try await setupCardReader(with: config)

            try transition(to: .ready)
            events.emit(.reinitializationCompleted)
        } catch {
            state = .error(error.localizedDescription)
            throw error
        }
    }

    var isReady: Bool {
        state == .ready
    }

    // MARK: - Phase A: Attestation

    private func performAttestationIfNeeded() async throws {
        guard attester.needsAttestation else { return }

        let challengeResponse = try await attestationService.fetchChallenge()

        guard let challengeData = Data(base64Encoded: challengeResponse.challenge) else {
            throw PayabliTTPError.attestationFailed("Invalid challenge format from backend")
        }

        let keyId = try await attester.generateKey()
        let attestation = try await attester.attestKey(keyId, challenge: challengeData)

        try await attestationService.registerAttestation(
            challengeId: challengeResponse.challengeId,
            keyId: keyId,
            attestation: attestation,
            deviceId: deviceId
        )
        try attester.persistKeyId(keyId)
    }

    // MARK: - Phase B: Config

    private func fetchConfig() async throws -> ConfigResponse {
        guard let keyId = attester.keyId else {
            throw PayabliTTPError.attestationFailed("No attested keyId available")
        }

        let assertionData = try JSONSerialization.data(
            withJSONObject: ["timestamp": ISO8601DateFormatter().string(from: Date())]
        )
        let assertion = try await attester.generateAssertion(requestData: assertionData)

        return try await attestationService.fetchConfig(assertion: assertion, keyId: keyId, deviceId: deviceId)
    }

    // MARK: - Phase C: Card Reader

    private func setupCardReader(with config: ConfigResponse) async throws {
        do {
            try cardReader.configure(with: config)
            try await cardReader.requestSessionToken()

            let linked = try await cardReader.isAccountLinked()
            if !linked {
                try await cardReader.linkAccount()
            }

            try await cardReader.initializeSession()
        } catch {
            throw PayabliTTPError.fiservError("Card reader setup failed: \(error.localizedDescription)")
        }
    }

    // MARK: - State Machine

    private func transition(to next: SessionState) throws {
        guard state.canTransition(to: next) else {
            throw PayabliTTPError.unknown(
                "Invalid state transition: \(state) → \(next)"
            )
        }
        state = next
    }
}

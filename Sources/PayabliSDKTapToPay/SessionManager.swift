import Combine
import Foundation

/// Manages the TTP session lifecycle (PRD §17).
///
/// State transitions are enforced internally. Host apps observe state via
/// `@Published sessionState`. All transitions occur on `@MainActor` for safe
/// SwiftUI observation (§17.4).
/// Which entry point is building the session, so the two can be told apart when
/// one is already running.
enum SessionSetupKind {
    case initialize
    case reinitialize
    case activate
}

@MainActor
final class SessionManager: ObservableObject {
    @Published private(set) var sessionState: PayabliTTPSessionState = .idle
    @Published private(set) var isReady: Bool = false
    private(set) var lastError: Error?

    init() {}

    /// Attempt to transition to a new state. Rejects invalid transitions.
    @discardableResult
    func transition(to target: PayabliTTPSessionState) -> Bool {
        guard Self.isValidTransition(from: sessionState, to: target) else {
            return false
        }
        sessionState = target
        isReady = (target == .ready)
        return true
    }

    /// Forces `.sessionExpired`, bypassing the transition matrix.
    ///
    /// Nothing calls this, and its doc claimed "called on 401s", which no code
    /// did. Scheduled for deletion; use `transition(to:)`, which the matrix
    /// still governs.
    private func forceSessionExpiry() {
        if sessionState != .sessionExpired {
            sessionState = .sessionExpired
            isReady = false
        }
    }

    /// Lands a failure where the map says it lands. A failure that leaves the
    /// session where it was moves nothing but `lastError`.
    func markError(_ error: Error, registration: StoredRegistration) {
        lastError = error
        guard let landing = PayabliTTPSessionState.landing(for: error, registration: registration) else { return }
        sessionState = landing
        isReady = (landing == .ready)
    }

    /// Records how far the reader has got, without leaving the state it belongs
    /// to. Does nothing unless a configuration is running, so a percentage
    /// cannot exist outside one.
    func recordConfigurationProgress(_ percent: Int) {
        guard case .initializingReader = sessionState else { return }
        sessionState = .initializingReader(percent: percent)
    }

    /// The charge holding the session, or `nil` when none does.
    private(set) var runningCharge: Int?
    private var nextCharge = 0

    /// Enters a charge and names it, or answers `nil` when the session is not
    /// ready. The ready check and the entry are one write, so a second charge is
    /// refused while one holds the reader.
    func beginCharge() -> Int? {
        guard sessionState == .ready, transition(to: .charging(activity: .opening)) else { return nil }
        nextCharge += 1
        runningCharge = nextCharge
        return nextCharge
    }

    /// Dropped unless `charge` still holds the session.
    func recordChargeActivity(_ activity: TapToPayChargeActivity, for charge: Int) {
        guard charge == runningCharge, case .charging = sessionState else { return }
        transition(to: .charging(activity: activity))
    }

    /// Returns to ready only while `charge` still holds the session, so a move
    /// made during the charge, by it or by another caller, is kept.
    func endCharge(_ charge: Int) {
        guard charge == runningCharge else { return }
        runningCharge = nil
        guard case .charging = sessionState else { return }
        transition(to: .ready)
    }

    /// Returns the session to its starting point. Internal: a host reaches this
    /// only through `initialize()`, never as an operation of its own.
    func reset() {
        transition(to: .idle)
        lastError = nil
    }

    // MARK: - Transition matrix (PRD §17.2)

    static func isValidTransition(
        from current: PayabliTTPSessionState,
        to target: PayabliTTPSessionState
    ) -> Bool {
        if case let .charging(activity) = current {
            return chargeMayMove(from: activity, to: target)
        }
        return isValidSessionTransition(from: current, to: target)
    }

    private static func isValidSessionTransition(
        from current: PayabliTTPSessionState,
        to target: PayabliTTPSessionState
    ) -> Bool {
        // Identity (re-entering same state) is allowed but not counted.
        if current == target {
            return true
        }

        switch (current, target) {
        // Starting over is always reachable. `initialize()` is the documented
        // way back to a known state, and it has to work from wherever the
        // session was left.
        case (_, .idle):
            return true

        case (.idle, .attestingDevice),
             (.idle, .fetchingConfig):
            return true

        case (.attestingDevice, .fetchingConfig),
             (.attestingDevice, .pendingActivation),
             (.attestingDevice, .failed):
            return true

        case (.fetchingConfig, .initializingReader),
             (.fetchingConfig, .pendingActivation),
             (.fetchingConfig, .failed):
            return true

        case (.initializingReader, .ready),
             (.initializingReader, .pendingTerms),
             (.initializingReader, .failed):
            return true

        case (.ready, .sessionExpired),
             (.ready, .failed),
             (.ready, .charging(.opening)):
            return true

        case (.sessionExpired, .reinitializing):
            return true

        case (.reinitializing, .fetchingConfig),
             (.reinitializing, .failed):
            return true

        // Both wait on a person rather than on the SDK, and both leave the same way: the host resolves
        // what the session is waiting on, then initializes again, which starts at attestation.
        case (.pendingActivation, .attestingDevice),
             (.pendingTerms, .attestingDevice):
            return true

        case (.failed, .attestingDevice),
             (.failed, .fetchingConfig):
            return true

        default:
            return false
        }
    }

    /// A charge ends back at ready whatever it ended in, or expired when the
    /// read found the reader session spent, and starting over is always reachable.
    private static func chargeMayMove(from activity: TapToPayChargeActivity, to target: PayabliTTPSessionState) -> Bool {
        switch target {
        case .idle, .ready, .sessionExpired:
            return true
        case let .charging(next):
            return next == activity || advances(activity, next)
        default:
            return false
        }
    }

    /// A charge opens, waits for a card, then closes. While it waits, the
    /// reader's prompts follow each other in whatever order the payer causes.
    private static func advances(_ from: TapToPayChargeActivity, _ to: TapToPayChargeActivity) -> Bool {
        switch from {
        case .opening:
            return to == .waitingForCard
        case .waitingForCard, .cardDetected, .cardRemovalRequested, .cardReadRetryRequested,
             .pinEntryRequested, .pinEntryCompleted, .readerPromptDismissed:
            return to != .opening
        case .closing:
            return false
        }
    }
}

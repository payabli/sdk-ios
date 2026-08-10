import Foundation
import Combine

/// Manages the 9-state TTP session lifecycle (PRD §17).
///
/// State transitions are enforced internally. Host apps observe state via
/// `@Published sessionState`. All transitions occur on `@MainActor` for safe
/// SwiftUI observation (§17.4).
@MainActor
internal final class SessionManager: ObservableObject {
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

    func markError(_ error: Error) {
        lastError = error
        sessionState = .error
        isReady = false
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
        // Identity (re-entering same state) is allowed but not counted.
        if current == target { return true }

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
             (.attestingDevice, .error):
            return true

        case (.fetchingConfig, .initializingReader),
             (.fetchingConfig, .pendingActivation),
             (.fetchingConfig, .error):
            return true

        case (.initializingReader, .ready),
             (.initializingReader, .error):
            return true

        case (.ready, .sessionExpired),
             (.ready, .error):
            return true

        case (.sessionExpired, .reinitializing):
            return true

        case (.reinitializing, .fetchingConfig),
             (.reinitializing, .error):
            return true

        case (.pendingActivation, .attestingDevice):
            return true

        case (.error, .attestingDevice),
             (.error, .fetchingConfig):
            return true

        default:
            return false
        }
    }
}

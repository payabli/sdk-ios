import Foundation

/// Formal state machine for the SDK session lifecycle.
/// Each state has a defined set of valid transitions.
///
/// Flow:  idle → attestingDevice → fetchingConfig → initializingReader → ready
///        ready → sessionExpired → reinitializing → ready
///        any   → error
public enum SessionState: Sendable, Equatable {
    case idle
    case attestingDevice
    case fetchingConfig
    case initializingReader
    case ready
    case sessionExpired
    case reinitializing
    case error(String)

    /// Valid next states from the current state.
    var validTransitions: [SessionState] {
        switch self {
        case .idle:
            return [.attestingDevice, .error("")]
        case .attestingDevice:
            return [.fetchingConfig, .error("")]
        case .fetchingConfig:
            return [.initializingReader, .error("")]
        case .initializingReader:
            return [.ready, .error("")]
        case .ready:
            return [.sessionExpired]
        case .sessionExpired:
            return [.reinitializing, .error("")]
        case .reinitializing:
            return [.ready, .error("")]
        case .error:
            return [.idle, .attestingDevice, .reinitializing]
        }
    }

    /// Returns true if transitioning to `next` is valid.
    func canTransition(to next: SessionState) -> Bool {
        if case .error = next { return true }
        return validTransitions.contains(where: { $0.caseTag == next.caseTag })
    }

    /// Stable case discriminator without relying on Mirror reflection.
    private var caseTag: Int {
        switch self {
        case .idle: return 0
        case .attestingDevice: return 1
        case .fetchingConfig: return 2
        case .initializingReader: return 3
        case .ready: return 4
        case .sessionExpired: return 5
        case .reinitializing: return 6
        case .error: return 7
        }
    }
}

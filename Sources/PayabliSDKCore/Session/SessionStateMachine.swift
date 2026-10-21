import Foundation

/// What the SDK can do right now: one value per process, readable before any session exists.
enum SdkState: Sendable, Equatable {
    case uninitialized
    case ready
    case reinitializeRequired

    /// The name for a log record or a report, from a closed set.
    var diagnosticName: String {
        switch self {
        case .uninitialized: "uninitialized"
        case .ready: "ready"
        case .reinitializeRequired: "reinitialize_required"
        }
    }
}

/// Where the one `SdkState` lives. It outlives every session, so each session's machine is handed it.
final class SdkStateSink: @unchecked Sendable {
    private let lock = NSLock()
    private var current: SdkState

    /// - Parameter initial: the value before any machine writes, `uninitialized` for the process's own sink.
    init(_ initial: SdkState = .uninitialized) {
        current = initial
    }

    var value: SdkState {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}

/// The only writer of the `SdkState` a sink holds. **A finished machine never writes again**: a successor may
/// publish `ready` over its predecessor's terminal value, and a request that resumes under the predecessor
/// cannot publish over the successor.
final class SessionStateMachine: @unchecked Sendable {
    private let sink: SdkStateSink
    private let logger: PayabliLogger

    /// Holds `finished` and the write it explains together, so the two are one step to any observer. Raised after
    /// the write, a caller reacting to the terminal value still reads this machine as usable; raised before, a
    /// successor can be installed while the write is still to land on top of it.
    private let guardLock = NSLock()
    private var finished = false

    /// - Parameter sink: the process's state, which this machine writes until it is finished.
    /// - Parameter logger: where refused and published transitions are recorded.
    init(sink: SdkStateSink, logger: PayabliLogger = PayabliLogger(category: .core)) {
        self.sink = sink
        self.logger = logger
    }

    /// True once this machine is finished, whether it published the fact or was retired by `finish()`.
    var isFinished: Bool {
        guardLock.withLock { finished }
    }

    /// Retires this machine without publishing anything.
    ///
    /// For a session dropped without reaching the terminal state, where whatever replaces it publishes its own
    /// value. Publishing here as well would announce a terminal state that never became true.
    func finish() {
        guardLock.withLock { finished = true }
    }

    /// `initialize` succeeded.
    func markReady() {
        transition(to: .ready)
    }

    /// The credential is finished, so the host has to re-initialize.
    ///
    /// Idempotent: several requests in flight can each discover the same finished session, and the second to
    /// notice changes nothing.
    func markReinitializeRequired() {
        transition(to: .reinitializeRequired)
    }

    /// Decides and writes under the lock, so a refused transition is never briefly published. Both records are
    /// written after the lock is released.
    ///
    /// - Parameter target: the state to write.
    private func transition(to target: SdkState) {
        let (refused, published) = guardLock.withLock { () -> (Bool, Bool) in
            if finished {
                // Silent for the terminal target: several requests discovering the same finished session is
                // the documented case. Anything else is an attempt to revive it.
                return (target != .reinitializeRequired, false)
            }
            guard sink.value != target else { return (false, false) }
            if target == .reinitializeRequired {
                finished = true
            }
            sink.value = target
            return (false, true)
        }

        if refused {
            logger.warning("session_state_refused state=\(target.diagnosticName)")
        }
        if published {
            logger.info("session_state state=\(target.diagnosticName)")
        }
    }
}

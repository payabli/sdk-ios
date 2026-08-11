/// Where one step of a flow has got to.
enum StepStatus {
    /// Finished, and nothing more to do here.
    case done
    /// The next thing to do.
    case current
    /// Underway inside the SDK; the app is waiting, not the person.
    case inProgress
    /// Cannot run until an earlier step finishes.
    case blocked
    /// Genuinely does not apply to this device or session.
    case notNeeded
    /// Attempted and failed.
    case failed

    /// Whether this step shows its controls.
    var showsContent: Bool {
        self == .current || self == .failed
    }

    /// Whether this step is the one asking for something. Narrower than
    /// `showsContent`.
    var isActionable: Bool {
        self == .current || self == .failed
    }

    /// Whether the step after this one may proceed. A skipped step counts as
    /// finished.
    ///
    /// A step that reads the state underneath instead can offer itself alongside
    /// an earlier step that is still asking for something.
    var isFinished: Bool {
        self == .done || self == .notNeeded
    }
}

/// One step, as a screen describes it.
///
/// - Parameters:
///   - title: what the person is doing.
///   - detail: what the SDK does at this point, in one line.
struct FlowStep {
    let title: String
    let detail: String
    let status: StepStatus
}

/// What the token probe last said.
///
/// Each screen records the probe as display text, and this is where the text
/// becomes an answer.
enum TokenCheck {
    /// The probe has not been run.
    case notRun
    /// The probe is in flight.
    case checking
    /// The endpoint returned a token.
    case reachable
    /// The endpoint did not.
    case unreachable

    static func classify(_ text: String) -> TokenCheck {
        if text.hasPrefix("✓") {
            return .reachable
        }
        if text.hasPrefix("✗") {
            return .unreachable
        }
        if text.hasPrefix("Checking") {
            return .checking
        }
        return .notRun
    }
}


/// Which half of the activation step happened.
///
/// Activation is two SDK calls. `sessionState` cannot tell them apart: both land
/// in `.error`, except a revoked attestation, which lands in `.idle`.
enum TapToPayActivationOutcome {
    case none
    case activationFailed
    /// The attestation behind the activation was revoked. `activateDevice`
    /// resets the session to `.idle` for this case alone, and the way out is a
    /// fresh cold attestation, which is the enable step's job.
    case attestationRevoked
    case enableFailed
    case succeeded
}

/// The four steps of taking a contactless payment, in the order the SDK needs
/// them.
struct TapToPayFlowSteps {
    let token: FlowStep
    let enable: FlowStep
    let activation: FlowStep
    let charge: FlowStep

    /// The one control the screen offers, or none while the SDK is working.
    ///
    /// A step reports where it has got to; this says which control a person can
    /// press. They are separate because a step reports a failure it cannot
    /// retry: a refused activation leaves the session `.error`, and
    /// `activateDevice` throws `.invalidState` for anything but
    /// `.pendingActivation`, so the activation step shows the reason while
    /// recovery is the way forward.
    ///
    /// Recovery lives here for the same reason. It is not a step, and while it
    /// was a flag of its own it appeared beside a step still asking for
    /// something.
    let nextAction: TapToPayAction?

    /// Why recovery is on offer, which is what the section says out loud.
    ///
    /// Two reasons and two controls, one each, as it stands. The sentence is
    /// keyed on the reason because a control serves whichever reasons share it:
    /// `.reinitialize` answered both an expired session and a refused activation
    /// until the DeviceCheck path was traced, and the sentence beside it named
    /// expiry for both.
    let recovery: TapToPayRecovery?

    var all: [FlowStep] {
        [token, enable, activation, charge]
    }
}

/// What the screen is recovering from.
enum TapToPayRecovery {
    /// The session expired holding its attested identity.
    case sessionExpired
    /// The session errored. Some of the paths here clear the attested identity
    /// and the rest keep it, and which one ran is not knowable from the outside,
    /// so recovery runs the setup that works for both.
    ///
    /// A failed activation is one of them. `.activationFailed` does not
    /// establish that `/activate` reached the backend: `generateAssertion`
    /// clears the cached key and device on a DeviceCheck error and throws before
    /// the request is sent, and that error is not a reader failure, so it
    /// arrives as a plain `.activationFailed` with the identity already gone.
    /// Only a 401 from `/activate` itself is reported as `.attestationRevoked`.
    case sessionErrored
}

/// A control on the Tap to Pay screen.
enum TapToPayAction {
    case checkToken
    case enableTerminal
    case enterActivationCode
    case charge
    /// `reinitializeIfNeeded`, which re-runs config and the reader and skips
    /// attestation. Only sound where the attested identity is still held.
    case reinitialize
    /// `initialize`, the full setup. It re-uses a cached attestation and runs a
    /// cold one when there is none, so it is the way back from a session that
    /// still holds its attested identity and from one that has lost it.
    case reattest
}

/// What taking a contactless payment asks for.
enum TapToPaySteps {
    /// - Parameters:
    ///   - tokenCheck: what the token probe last said.
    ///   - session: where the terminal session has got to.
    ///   - outcome: what the last activation attempt did.
    static func forCharging(
        tokenCheck: TokenCheck,
        session: TapToPaySessionStatus,
        activation outcome: TapToPayActivationOutcome
    ) -> TapToPayFlowSteps {
        // States the session cannot reach without a successful authenticated
        // request. `.attestingDevice` is set before that request, and `.error` is
        // where a failing token provider lands.
        let sessionProvesBackend = switch session {
        case .fetchingConfig, .initializingReader, .ready, .pendingActivation, .reinitializing:
            true
        default:
            false
        }

        let token: StepStatus = {
            switch tokenCheck {
            // Before the outcome, or the step offers its button over a request
            // already in flight.
            case .checking: return .inProgress
            // The probe outranks the session, which says only that the backend
            // answered at some point in the past.
            case .unreachable: return .failed
            case .reachable: return .done
            case .notRun: return sessionProvesBackend ? .done : .current
            }
        }()

        let enable: StepStatus = {
            guard token.isFinished else { return .blocked }
            switch session {
            case .ready: return .done
            case .attestingDevice, .fetchingConfig, .initializingReader, .reinitializing: return .inProgress
            // Activation is a separate step, so reaching it means this one
            // finished — unless the enable that follows a successful activation
            // is what failed. `/config` answering 403 again puts the session back
            // to `.pendingActivation`, and the reason for that failure is written
            // to this step.
            case .pendingActivation: return outcome == .enableFailed ? .failed : .done
            // `activateDevice` calls markError when it is refused, so the session
            // reads `.error` for a failure that belongs to the step after this
            // one. Taking it here would block activation, which is where the
            // reason and the retry are rendered. Expiry is not activation's
            // doing, so a stale outcome does not move it.
            case .error: return outcome == .activationFailed ? .done : .failed
            case .sessionExpired: return .failed
            // A recorded activation failure at `.idle` is a revoked attestation:
            // it is the one failure `activateDevice` resets rather than marks,
            // and re-attesting from scratch is this step's own action.
            case .idle:
                return outcome == .attestationRevoked || outcome == .activationFailed
                    ? .failed
                    : .current
            // A state this app does not name says nothing about whether the reader
            // came up, so the step stays the one to act on.
            case .unrecognised: return .current
            }
        }()

        let activation: StepStatus = {
            // Ordered. The outcome outlives the session it belongs to, so reading
            // it first lets a stale failure report itself while the sequence is
            // still on the step before.
            guard enable == .done else { return .blocked }
            // A session reports `.ready` for a device that was activated and for
            // one that never had to be. Only the caller can tell them apart.
            if outcome == .succeeded {
                return .done
            }
            if session == .ready {
                return .notNeeded
            }
            // What is left is `.pendingActivation`, or the `.error` the step
            // before handed on because a refused activation put it there.
            return outcome == .activationFailed ? .failed : .current
        }()

        // From the step before.
        let charge: StepStatus = {
            guard activation.isFinished else { return .blocked }
            return session == .ready ? .current : .blocked
        }()

        // Ordered like the steps, and for the same reason: the first thing that
        // wants attention is the only thing offered. Re-initialize sits behind
        // the token step because it re-runs config, which a backend known to be
        // down cannot answer.
        // Derived before `nextAction`, which reads it, so the control and the
        // sentence beside it cannot disagree about what went wrong.
        let recovery: TapToPayRecovery? = {
            guard !token.isActionable, token.isFinished else { return nil }
            if session == .sessionExpired {
                return .sessionExpired
            }
            if session == .error {
                return .sessionErrored
            }
            return nil
        }()

        let nextAction: TapToPayAction? = {
            if token.isActionable {
                return .checkToken
            }
            guard token.isFinished else { return nil }
            // A session that expired still holds its attested identity, so
            // re-running config and the reader is enough, and so does a refused
            // activation, whose request reached the backend. `.error` otherwise
            // is where a config 401 lands, and that path clears the attestation
            // cache, so skipping attestation would fail on the assertion every
            // time and offer the same control again.
            if let recovery {
                return recovery == .sessionErrored ? .reattest : .reinitialize
            }
            // `.failed` as well as `.current`: an enable that failed is retried
            // from its own row, and this is the state a broken session does not
            // cover.
            if enable.isActionable {
                return .enableTerminal
            }
            guard enable.isFinished else { return nil }
            // `.failed` as well as `.current`, as with the enable step above: a
            // refused code leaves the session `.pendingActivation`, which is the
            // one state `activateDevice` accepts, so another code is the way on.
            if activation.isActionable {
                return .enterActivationCode
            }
            guard activation.isFinished else { return nil }
            return charge == .current ? .charge : nil
        }()

        return TapToPayFlowSteps(
            token: FlowStep(
                title: "Reach the token backend",
                detail: "The SDK calls your backend for a fresh access token whenever it needs one.",
                status: token
            ),
            enable: FlowStep(
                title: "Enable the terminal",
                detail: "Attests the device, fetches the merchant config, and prepares the reader.",
                status: enable
            ),
            activation: FlowStep(
                title: "Activate the device",
                detail: session == .pendingActivation
                    ? "Activate the device with the code provided by the Paypoint Device Management dashboard."
                    : "Only when the backend registers the device as pending.",
                status: activation
            ),
            charge: FlowStep(
                title: "Charge a card",
                detail: "Presents Apple's Tap to Pay sheet. Hold a card to the top of the phone.",
                status: charge
            ),
            nextAction: nextAction,
            recovery: recovery
        )
    }
}

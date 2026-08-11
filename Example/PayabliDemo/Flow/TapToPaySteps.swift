import PayabliSDKTapToPay

/// Which half of the activation step happened.
///
/// Activation is two SDK calls. `sessionState` cannot tell them apart: both land
/// in `.error`, except a revoked attestation, which lands in `.idle`.
enum TapToPayActivationOutcome {
    case none
    case activationFailed
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

    var all: [FlowStep] {
        [token, enable, activation, charge]
    }
}

/// What taking a contactless payment asks for.
enum TapToPaySteps {
    /// - Parameters:
    ///   - tokenCheck: what the token probe last said.
    ///   - session: where the terminal session has got to.
    ///   - outcome: what the last activation attempt did.
    static func forCharging(
        tokenCheck: TokenCheck,
        session: PayabliTTPSessionState,
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
            // Activation is a separate step, so reaching it means this one finished.
            case .pendingActivation: return .done
            // `activateDevice` calls markError when it is refused, so the session
            // reads `.error` for a failure that belongs to the step after this
            // one. Taking it here would block activation, which is where the
            // reason and the retry are rendered. Expiry is not activation's
            // doing, so a stale outcome does not move it.
            case .error: return outcome == .activationFailed ? .done : .failed
            case .sessionExpired: return .failed
            case .idle: return .current
            @unknown default: return .current
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

        // From the step before, not the session.
        let charge: StepStatus = {
            guard activation.isFinished else { return .blocked }
            return session == .ready ? .current : .blocked
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
            )
        )
    }
}

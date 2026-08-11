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
        // True once the backend is known reachable — either because the probe was
        // run, or because the SDK already fetched a token to get past `idle`.
        //
        // Only states the session cannot reach without a successful authenticated
        // request. `.attestingDevice` is set before that request, and `.error` is
        // where a failing token provider lands, so neither proves anything.
        let backendProven = switch session {
        case .fetchingConfig, .initializingReader, .ready, .pendingActivation, .reinitializing:
            true
        default:
            tokenCheck == .reachable
        }

        let token: StepStatus = {
            if tokenCheck == .unreachable {
                return .failed
            }
            return backendProven ? .done : .current
        }()

        let enable: StepStatus = {
            // Exactly one step is ever `.current`, so this stays blocked until the
            // backend is proven rather than competing with step 1 for attention.
            guard backendProven else { return .blocked }
            switch session {
            case .ready: return .done
            case .attestingDevice, .fetchingConfig, .initializingReader, .reinitializing: return .inProgress
            // Activation is a separate step, so reaching it means this one finished.
            case .pendingActivation: return .done
            case .error, .sessionExpired: return .failed
            case .idle: return .current
            @unknown default: return .current
            }
        }()

        let activation: StepStatus = {
            // A failed activation must stay actionable: `.failed` is the only other
            // status whose content renders, so blocking it would hide the reason and
            // the retry together. Read from the recorded outcome rather than from
            // `sessionState`, which cannot distinguish the two calls this step makes
            // and reports `.idle` for a revoked attestation.
            if outcome == .activationFailed {
                return .failed
            }
            switch session {
            case .pendingActivation: return .current
            case .ready: return .notNeeded
            default: return .blocked
            }
        }()

        let charge: StepStatus = session == .ready ? .current : .blocked

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

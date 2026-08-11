/// How far a card-not-present screen has got.
///
/// - Parameters:
///   - tokenCheck: what the token probe last said.
///   - hasResult: a submission returned. The component keeps this forever and
///     exposes no reset.
///   - resultAcknowledged: the result has been read and another entry is wanted.
///   - isSubmitting: the SDK is submitting.
///   - submitFailed: the last submission failed, or came back carrying nothing.
struct PayInProgress {
    var tokenCheck: TokenCheck = .notRun
    var hasResult = false
    var resultAcknowledged = false
    var isSubmitting = false
    var submitFailed = false
}

/// The three steps of a card-not-present screen.
struct PayInFlowSteps {
    let backend: FlowStep
    let form: FlowStep
    let result: FlowStep

    var all: [FlowStep] {
        [backend, form, result]
    }
}

/// What a card-not-present screen asks for, in the order the SDK needs it.
enum PayInSteps {
    /// Storing an instrument, which returns a token to reuse.
    static func forStoringMethod(_ progress: PayInProgress) -> PayInFlowSteps {
        steps(
            progress,
            formTitle: "Enter the card or ACH details",
            resultTitle: "Stored method",
            resultDetail: "A successful submit returns a reusable stored-method id."
        )
    }

    /// Taking a payment now.
    static func forCapture(_ progress: PayInProgress) -> PayInFlowSteps {
        steps(
            progress,
            formTitle: "Enter the payment details",
            resultTitle: "Transaction",
            resultDetail: "A successful submit returns an approved transaction id."
        )
    }

    private static func steps(
        _ progress: PayInProgress,
        formTitle: String,
        resultTitle: String,
        resultDetail: String
    ) -> PayInFlowSteps {
        // True once the backend is known reachable — either the probe was run, or
        // a submit already succeeded, which proves it just as well.
        let backendProven = progress.tokenCheck == .reachable || progress.hasResult
        let showingFinishedResult = progress.hasResult && !progress.resultAcknowledged

        let backend: StepStatus = {
            if progress.tokenCheck == .unreachable {
                return .failed
            }
            return backendProven ? .done : .current
        }()

        let form: StepStatus = {
            // Exactly one step is ever `.current`, so this waits rather than
            // competing with step 1 for attention.
            guard backendProven else { return .blocked }
            if progress.isSubmitting {
                return .inProgress
            }
            if progress.submitFailed {
                return .failed
            }
            return showingFinishedResult ? .done : .current
        }()

        let result: StepStatus = {
            // A failure belongs to the step that produced it. Marking this one
            // failed too would give the sequence two actionable failures.
            if progress.submitFailed {
                return .blocked
            }
            return showingFinishedResult ? .current : .blocked
        }()

        return PayInFlowSteps(
            backend: FlowStep(
                title: "Reach the token backend",
                detail: "The SDK asks your backend for a short-lived access token before it submits.",
                status: backend
            ),
            form: FlowStep(
                title: formTitle,
                detail: "The SDK owns these fields; clear PAN never reaches the host app.",
                status: form
            ),
            result: FlowStep(title: resultTitle, detail: resultDetail, status: result)
        )
    }
}

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
        let showingFinishedResult = progress.hasResult && !progress.resultAcknowledged

        let backend: StepStatus = {
            // A submission in flight got a token to submit with, so this step is
            // finished for as long as it lasts. The probe is shared, so another
            // tab can answer for this endpoint mid-submit; letting that unfinish
            // this step would block the form, hide the row, and deallocate the
            // view model holding what was typed. The answer applies once the
            // submission is over, which is when it says anything about the next
            // one.
            if progress.isSubmitting {
                return .done
            }
            switch progress.tokenCheck {
            // Before the outcome, or the step offers its button over a request
            // already in flight.
            case .checking: return .inProgress
            // The probe outranks a submission that succeeded earlier. The
            // component never clears `lastResult`, so one payment would otherwise
            // prove the backend for the life of the app.
            case .unreachable: return .failed
            case .reachable: return .done
            case .notRun: return progress.hasResult ? .done : .current
            }
        }()

        let form: StepStatus = {
            guard backend.isFinished else { return .blocked }
            if progress.isSubmitting {
                return .inProgress
            }
            if progress.submitFailed {
                return .failed
            }
            return showingFinishedResult ? .done : .current
        }()

        // From the step before. `hasResult` can be true while the form is still
        // asking for something.
        let result: StepStatus = form.isFinished ? .current : .blocked

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

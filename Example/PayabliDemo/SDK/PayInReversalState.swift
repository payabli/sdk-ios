/// What a screen knows about reversing the payments it has taken.
///
/// Its own type rather than a handful of view properties, because the transitions decide whether a
/// payment can be reversed twice. A screen holding them as separate flags can only be checked by
/// driving the screen, and the branch that matters most is the one a live walkthrough never reaches:
/// a reversal that never answered.
///
/// Nothing here decides whose answer arrived. The transaction is passed in by the caller that asked
/// about it, and `onScreen` is the payment the screen is showing, so an answer for a payment that has
/// since been replaced changes what is known without being displayed.
struct PayInReversalState: Equatable {
    /// Whether this screen started a reversal that has not answered yet.
    ///
    /// What this screen did, which is its own fact. It is never a copy of whether the flow is
    /// submitting, and never decides whether a control may be pressed.
    private(set) var isReversing = false

    /// The payment this screen has reversed.
    private(set) var reversed: String?

    /// Payments whose reversal never answered, so nobody can say whether it applied.
    ///
    /// Kept per transaction rather than as one flag: a settled failure for one reversal says nothing
    /// about another that is still open, and the notice has to name which payment to read back.
    private(set) var unreconciled: [String] = []

    /// What the last reversal said about the payment on screen.
    private(set) var message = ""

    mutating func began() {
        isReversing = true
        message = ""
    }

    mutating func reversed(_ transId: String, saying text: String, onScreen: String?) {
        isReversing = false
        reversed = transId
        unreconciled.removeAll { $0 == transId }
        show(text, for: transId, onScreen: onScreen)
    }

    mutating func failed(_ failure: PayInFailure, for transId: String, onScreen: String?) {
        isReversing = false

        // A refusal because another submission was running is not this request's answer: the request
        // was never made, so it changes nothing about what is known of the payment. Before the
        // mutation below rather than after it, or the refusal clears a question raised by an earlier
        // attempt that is still open.
        guard !failure.refusedForAnotherSubmission else { return }

        if failure.outcomeIsUnresolved {
            if !unreconciled.contains(transId) {
                unreconciled.append(transId)
            }
        } else {
            unreconciled.removeAll { $0 == transId }
        }
        show(failure.message, for: transId, onScreen: onScreen)
    }

    /// The payment leaves the screen, and what was said about reversing it leaves with it.
    ///
    /// What nobody can account for stays: it outlives the payment, because reading that transaction
    /// back is the one thing left to do about it.
    mutating func paymentReplaced() {
        reversed = nil
        message = ""
    }

    /// Whether a reversal is still worth offering for this payment.
    func offersReversal(of transId: String) -> Bool {
        reversed != transId && !unreconciled.contains(transId)
    }

    private mutating func show(_ text: String, for transId: String, onScreen: String?) {
        guard onScreen == transId else { return }
        message = text
    }
}

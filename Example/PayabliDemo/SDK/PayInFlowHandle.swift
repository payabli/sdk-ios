import Combine
import PayabliSDKPayInPaymentFlow

/// A screen's grip on the flow it submits through.
///
/// The flow itself stays in here. A screen needs answers about it and the form
/// needs the flow, so this hands out the answers and keeps the type: outside this
/// group nothing names one, which is what makes the group the whole of the
/// integration rather than most of it.
@MainActor
final class PayInFlowHandle: ObservableObject {
    let flow: PayabliPayInPaymentFlow

    private var forwarding: AnyCancellable?

    init(_ flow: PayabliPayInPaymentFlow) {
        self.flow = flow
        // Screens observe this object, so the flow's publishes have to arrive here
        // or a submission redraws nothing.
        forwarding = flow.objectWillChange.sink { [weak self] _ in
            self?.objectWillChange.send()
        }
    }

    /// Whether a submission is in flight.
    var isSubmitting: Bool {
        flow.isSubmitting
    }

    /// Whether the flow is holding an outcome nobody has taken yet. The component
    /// keeps its last result and exposes no reset, so a screen tracks
    /// acknowledgement itself.
    var hasResult: Bool {
        flow.lastResult != nil
    }

    /// The figure this attempt will charge, formatted for display.
    ///
    /// The currency comes from the same payment details as the figure, so the two
    /// cannot disagree, and the reader's own locale decides the grouping and the
    /// decimal mark.
    var formattedTotal: String {
        guard let details = flow.requestConfiguration?.paymentDetails else { return "-" }
        return details.totalAmount.formatted(.currency(code: details.currency ?? "USD"))
    }

    /// Draws a new attempt: a fresh amount, a fresh idempotency key, and whatever
    /// the customer switch says now. This is the one place a key is minted, and it
    /// is the only action here that may charge a second time.
    ///
    /// Not while a submission is in flight. Its outcome is unknown until it answers,
    /// and the key is what lets the next submit be read as a repeat of it; minting
    /// another makes that submit a payment of its own. The screen keeps offering
    /// this while a retry runs, so the refusal lives here rather than on the button.
    func startNewAttempt(suppliesCustomer: Bool) {
        guard !flow.isSubmitting else { return }
        flow.configure(
            requestConfiguration: PayInRequests.freshCapture(suppliesCustomer: suppliesCustomer)
        )
    }

    /// Puts the customer the switch now names onto the attempt already on screen,
    /// leaving the amount, the order identifier and the key as they were.
    ///
    /// Not while a submission is in flight: replacing the configuration then loses
    /// the key that makes its retry safe.
    func applyCustomerChange(suppliesCustomer: Bool) {
        guard !flow.isSubmitting else { return }
        guard let current = flow.requestConfiguration else {
            flow.configure(requestConfiguration: PayInRequests.freshCapture(suppliesCustomer: suppliesCustomer))
            return
        }
        flow.configure(
            requestConfiguration: PayInRequests.sameAttempt(
                as: current,
                customerData: suppliesCustomer ? PayInDemoCustomer.customerData : nil,
                idempotencyKey: current.idempotencyKey
            )
        )
    }
}

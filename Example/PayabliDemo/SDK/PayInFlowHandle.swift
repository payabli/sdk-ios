import Combine
import PayabliSDKPayIn

/// A screen's grip on the flow it submits through.
///
/// The flow itself stays in here. A screen needs answers about it and the form
/// needs the flow, so this hands out the answers and keeps the type: outside this
/// group nothing names one, which is what makes the group the whole of the
/// integration rather than most of it.
@MainActor
final class PayInFlowHandle: ObservableObject {
    let flow: PayabliPayIn

    private var forwarding: AnyCancellable?

    init(_ flow: PayabliPayIn) {
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

    /// Draws a new attempt: a fresh amount, a new payment, and whatever the customer switch says now.
    ///
    /// Not while a submission is in flight; the screen keeps offering this then, so the refusal lives here.
    ///
    /// - Returns: whether an attempt was drawn; a screen clears the last failure on `true` only.
    func startNewAttempt(
        suppliesCustomer: Bool,
        amount: Double = QAAmount.random(),
        source: String = "ios-payment-capture-qa"
    ) -> Bool {
        guard !flow.isSubmitting else { return false }
        flow.configure(
            requestConfiguration: PayInRequests.freshCapture(
                suppliesCustomer: suppliesCustomer,
                amount: amount,
                source: source
            )
        )
        return true
    }

    /// Reverses a payment already taken, releasing an authorization's hold or undoing a capture that has not settled.
    ///
    /// The SDK chooses and keeps the key. A state the service will not reverse arrives as the refusal it sent.
    func voidTransaction(_ transId: String) async throws -> PayInOutcome {
        PayInOutcome(try await flow.voidTransaction(transId))
    }

    /// Reads a transaction back by its identifier.
    func readTransaction(_ transId: String) async throws -> PayabliPayInTransaction {
        try await flow.readTransaction(transId)
    }

    /// Puts the customer the switch now names onto the attempt already on screen,
    /// leaving the amount, the order identifier and any declared retry as they were.
    ///
    /// Not while a submission is in flight, whose configuration it would replace.
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
                attempt: current.attempt
            )
        )
    }

    /// After a charge whose outcome is unknown, declares the next submit a retry of it, so the SDK sends that
    /// attempt's key and the service refuses a repeat rather than charging twice.
    ///
    /// - Parameter failure: how the charge ended.
    func chargeFailed(_ failure: PayInFailure) {
        guard failure.outcomeIsUnresolved, !flow.isSubmitting, let current = flow.requestConfiguration else { return }
        flow.configure(
            requestConfiguration: PayInRequests.sameAttempt(
                as: current,
                customerData: current.customerData,
                attempt: .retry
            )
        )
    }
}

/// When each charging flow on a screen that offers several operations draws a new attempt.
///
/// Only a changed amount or a completed payment gives a flow a new attempt; anything else leaves it where it was.
@MainActor
struct PayInAttempts {
    private var amounts: [PayInOperation: Double] = [:]

    /// The amount entered, applied to the flow on screen. Starts a new attempt only when it is not
    /// the amount that flow's attempt already carries.
    mutating func apply(
        amount: Double,
        to flow: PayInFlowHandle,
        for operation: PayInOperation,
        suppliesCustomer: Bool,
        source: String
    ) {
        guard amounts[operation] != amount else { return }
        start(amount: amount, on: flow, for: operation, suppliesCustomer: suppliesCustomer, source: source)
    }

    /// A payment on `operation` went through, so that flow's next submit is a payment of its own.
    mutating func paymentCompleted(
        amount: Double,
        on flow: PayInFlowHandle,
        for operation: PayInOperation,
        suppliesCustomer: Bool,
        source: String
    ) {
        start(amount: amount, on: flow, for: operation, suppliesCustomer: suppliesCustomer, source: source)
    }

    private mutating func start(
        amount: Double,
        on flow: PayInFlowHandle,
        for operation: PayInOperation,
        suppliesCustomer: Bool,
        source: String
    ) {
        if flow.startNewAttempt(suppliesCustomer: suppliesCustomer, amount: amount, source: source) {
            amounts[operation] = amount
        }
    }
}

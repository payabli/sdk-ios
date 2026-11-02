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

    /// The payment a form on this flow sends next. A flow that only stores methods never sends it.
    @Published private(set) var request: PayabliPayInRequestConfiguration

    private var forwarding: AnyCancellable?

    init(
        _ flow: PayabliPayIn,
        request: PayabliPayInRequestConfiguration = PayInRequests.freshCapture(suppliesCustomer: true)
    ) {
        self.flow = flow
        self.request = request
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

    /// What a form on this flow submits for `purpose`, carrying the payment it sends next.
    ///
    /// A reversal runs as a direct call and is never drawn as a form; its case only keeps the switch total.
    ///
    /// - Parameter purpose: what the form is for.
    /// - Parameter storeOptions: what a stored method is sent with; read only when `purpose` stores one.
    /// - Returns: the operation to hand the form.
    func formOperation(
        for purpose: PayInOperation,
        storeOptions: PayabliPayInTokenStorageOptions = PayabliPayInTokenStorageOptions()
    ) -> PayabliPayInOperation {
        switch purpose {
        case .storedMethod: .storePaymentMethod(storeOptions)
        case .capture, .void: .capture(request)
        case .authorize: .authorize(request)
        }
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
        request = PayInRequests.freshCapture(suppliesCustomer: suppliesCustomer, amount: amount, source: source)
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
    /// Not while a submission is in flight, whose payment it would change on screen.
    func applyCustomerChange(suppliesCustomer: Bool) {
        guard !flow.isSubmitting else { return }
        request = PayInRequests.sameAttempt(
            as: request,
            customerData: suppliesCustomer ? PayInDemoCustomer.customerData : nil,
            attempt: request.attempt
        )
    }

    /// After a charge whose outcome is unknown, makes the next submit a retry of it: the same payment, so the SDK
    /// sends the key it holds for that payment's reference and the service refuses a repeat rather than charging twice.
    ///
    /// - Parameter failure: how the charge ended.
    func chargeFailed(_ failure: PayInFailure) {
        guard failure.outcomeIsUnresolved, !flow.isSubmitting else { return }
        request = PayInRequests.sameAttempt(as: request, customerData: request.customerData, attempt: .retry)
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

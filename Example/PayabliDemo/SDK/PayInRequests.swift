import Foundation
import PayabliSDKPayInPaymentFlow

/// What this app asks the service for, for one capture attempt.
enum PayInRequests {
    /// A capture's request configuration, with a key minted per attempt.
    ///
    /// One attempt is one payment, however many times it is submitted: a retry
    /// carries the same key, so the service answers from the attempt that already
    /// reached it. A payment of its own is a new configuration, which is what this
    /// builds, and the app builds the first at launch.
    ///
    /// The amount is drawn per attempt and the identifiers name this device and the
    /// moment, so a run over several devices at once produces rows a dashboard can
    /// attribute. The form collects no amount and no customer number, so both are
    /// decided here.
    ///
    /// - Parameter suppliesCustomer: whether the request names the customer, which
    ///   the app's customer switch decides. A value the payer types wins over this
    ///   one; the form has no such box.
    static func freshCapture(suppliesCustomer: Bool) -> PayabliPayInPaymentFlowRequestConfiguration {
        let identity = QAIdentity.current
        return PayabliPayInPaymentFlowRequestConfiguration(
            paymentDetails: PayabliPayInPaymentFlowPaymentDetails(
                totalAmount: QAAmount.random(),
                serviceFee: 0.10,
                currency: "USD"
            ),
            customerData: suppliesCustomer ? PayInDemoCustomer.customerData : nil,
            orderDescription: identity.note("capture"),
            orderId: identity.orderId(at: Date()),
            source: "ios-payment-capture-qa",
            idempotencyKey: UUID().uuidString,
            forceCustomerCreation: true
        )
    }

    /// The attempt on screen with one thing changed.
    ///
    /// The amount, the order identifier and the key are the attempt's identity.
    /// Moving the customer switch answers a different question, so it changes the
    /// customer alone: redrawing the amount would change the figure a payer is
    /// about to confirm, and a new key would make the next submit a second payment
    /// rather than a retry of this one.
    static func sameAttempt(
        as current: PayabliPayInPaymentFlowRequestConfiguration,
        customerData: PayabliPayInPaymentFlowCustomerData?,
        idempotencyKey: String?
    ) -> PayabliPayInPaymentFlowRequestConfiguration {
        // Every field, not the ones this sample happens to set: anything omitted
        // here is silently reset the moment the switch moves.
        PayabliPayInPaymentFlowRequestConfiguration(
            paymentDetails: current.paymentDetails,
            accountId: current.accountId,
            customerData: customerData,
            ipAddress: current.ipAddress,
            orderDescription: current.orderDescription,
            orderId: current.orderId,
            source: current.source,
            subdomain: current.subdomain,
            subscriptionId: current.subscriptionId,
            idempotencyKey: idempotencyKey,
            achValidation: current.achValidation,
            forceCustomerCreation: current.forceCustomerCreation,
            validation: current.validation
        )
    }
}

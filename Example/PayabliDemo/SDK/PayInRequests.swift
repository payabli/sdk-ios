import Foundation
import PayabliSDKCore
import PayabliSDKPayIn

/// What this app asks the service for, for one capture attempt.
enum PayInRequests {
    /// A capture's request configuration for a new payment, named by a reference of its own.
    ///
    /// The identifiers name this device and the moment, so a run over several devices produces rows a dashboard can
    /// attribute. The form collects no amount and no customer number, so both are decided here.
    ///
    /// - Parameter suppliesCustomer: whether the request names the customer; a value the payer types wins.
    static func freshCapture(
        suppliesCustomer: Bool,
        amount: Double = QAAmount.random(),
        source: String = "ios-payment-capture-qa"
    ) -> PayabliPayInRequestConfiguration {
        let identity = QAIdentity.current
        return PayabliPayInRequestConfiguration(
            paymentDetails: PayabliPayInPaymentDetails(
                totalAmount: amount,
                serviceFee: 0.10,
                currency: "USD"
            ),
            customerData: suppliesCustomer ? PayInDemoCustomer.customerData : nil,
            orderDescription: identity.note("capture"),
            orderId: identity.orderId(at: Date()),
            source: source,
            paymentReference: UUID().uuidString,
            forceCustomerCreation: true
        )
    }

    /// The attempt on screen with one thing changed.
    ///
    /// The amount, the order identifier and whether the next submit is a retry are the attempt's identity.
    static func sameAttempt(
        as current: PayabliPayInRequestConfiguration,
        customerData: PayabliPayInCustomerData?,
        attempt: PayabliAttempt
    ) -> PayabliPayInRequestConfiguration {
        // Every field, not the ones this sample happens to set: anything omitted
        // here is silently reset the moment the switch moves.
        PayabliPayInRequestConfiguration(
            paymentDetails: current.paymentDetails,
            accountId: current.accountId,
            customerData: customerData,
            ipAddress: current.ipAddress,
            orderDescription: current.orderDescription,
            orderId: current.orderId,
            source: current.source,
            subdomain: current.subdomain,
            subscriptionId: current.subscriptionId,
            paymentReference: current.paymentReference,
            attempt: attempt,
            achValidation: current.achValidation,
            forceCustomerCreation: current.forceCustomerCreation,
            validation: current.validation
        )
    }
}

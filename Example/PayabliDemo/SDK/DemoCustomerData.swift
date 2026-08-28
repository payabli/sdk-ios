import PayabliSDKPayInPaymentFlow
import PayabliSDKTapToPay

/// The stand-in customer this app sends on a card-not-present capture.
///
/// Whether it is sent at all is the app's switch to decide; what is sent is here.
enum PayInDemoCustomer {
    /// This device rather than one constant, because several devices run the
    /// card-not-present flows at once and a shared number would put every row on
    /// one record.
    static let customerData = PayabliPayInPaymentFlowCustomerData(
        customerNumber: QAIdentity.current.customerNumber
    )

    /// What the sample describes itself as sending, for the Configuration tab.
    static var summary: String {
        QAIdentity.current.summary
    }
}

/// The stand-in customer this app sends on a card-present charge.
enum TapToPayDemoCustomer {
    /// One fixed customer, not a generated one. The lookup matches on
    /// `customerNumber` within a paypoint, so a constant reuses a single record; a
    /// per-sale value would leave one behind for every coffee.
    static let customerData = PayabliTTPCustomerData(
        firstName: "Demo",
        lastName: "Customer",
        customerNumber: "DEMO-TAPTOPAY",
        billingEmail: "demo-taptopay@example.com"
    )

    /// An empty customer, for the run that asks the paypoint to accept one.
    static let none = PayabliTTPCustomerData()

    /// What the sample describes itself as sending, for the Configuration tab.
    static var summary: String {
        [
            customerData.fullName,
            customerData.customerNumber,
            customerData.billingEmail
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

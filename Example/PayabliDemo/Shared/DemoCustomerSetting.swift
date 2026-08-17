import Foundation
import PayabliSDKPayInPaymentFlow
import PayabliSDKTapToPay
import SwiftUI

/// Whether the sample supplies a stand-in customer or asks for one.
///
/// A paypoint carries a list of custom identifiers, and a sale must satisfy it:
/// with `email` configured the request needs a `billingEmail`, with none
/// configured an empty customer is accepted and no customer record is written
/// at all. Which one a paypoint has is a merchant setting the SDK cannot see,
/// so the sample offers both and defaults to the one that works on either.
///
/// Not persisted: it describes the paypoint under test, which changes with the
/// environment, so a stored answer would outlive the paypoint it was true for.
@MainActor
final class DemoCustomerSetting: ObservableObject {
    @Published var suppliesDemoCustomer = true

    /// The same question for a card-not-present capture, and a separate answer
    /// because the two surfaces send different things.
    ///
    /// A paypoint matches a customer on its number, so sending one attaches every
    /// capture from this device to a single record. Sending none, with
    /// `forceCustomerCreation` set, leaves it nothing to match on and it files a
    /// new customer per payment: three captures from one device produced three
    /// customers with no number at all.
    ///
    /// The number and not the customer. The form's first name, last name and
    /// billing email are written over whatever this configures, so a capture with
    /// none configured still names a payer.
    @Published var suppliesPayInCustomer = true

    /// This device rather than one constant, because several devices run the
    /// card-not-present flows at once and a shared number would put every row on
    /// one record.
    static let payInCustomer = PayabliPayInPaymentFlowCustomerData(
        customerNumber: QAIdentity.current.customerNumber
    )

    /// What the sample describes itself as sending, for the Configuration tab.
    static var payInCustomerSummary: String {
        QAIdentity.current.summary
    }

    /// One fixed customer, not a generated one. The lookup matches on
    /// `customerNumber` within a paypoint, so a constant reuses a single
    /// record; a per-sale value would leave one behind for every coffee.
    static let demoCustomer = PayabliTTPCustomerData(
        firstName: "Demo",
        lastName: "Customer",
        customerNumber: "DEMO-TAPTOPAY",
        billingEmail: "demo-taptopay@example.com"
    )

    /// What the sample describes itself as sending, for the Configuration tab.
    static var demoCustomerSummary: String {
        [
            demoCustomer.fullName,
            demoCustomer.customerNumber,
            demoCustomer.billingEmail
        ]
        .compactMap { $0 }
        .joined(separator: " · ")
    }
}

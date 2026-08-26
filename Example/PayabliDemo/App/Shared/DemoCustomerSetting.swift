import Foundation
import SwiftUI

/// Whether the sample supplies a stand-in customer or asks for one.
///
/// A paypoint carries a list of custom identifiers, and a sale must satisfy it:
/// with `email` configured the request needs a `billingEmail`, with none
/// configured an empty customer is accepted and no customer record is written
/// at all. Which one a paypoint has is a merchant setting the SDK cannot see,
/// so the sample offers both and defaults to the one that works on either.
///
/// Only the answers live here. What is actually sent on each surface is in the
/// SDK group, beside the calls that send it.
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
}

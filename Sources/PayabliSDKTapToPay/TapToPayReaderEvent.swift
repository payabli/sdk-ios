import Foundation

/// What the card reader is doing, in the SDK's own terms.
///
/// An adapter converts its platform's event stream into this, so nothing above
/// the adapter speaks a vendor's vocabulary. A platform case with no member
/// here is dropped rather than added: the facade already announces the start,
/// the completion and the failure of a read, and a second announcement of one
/// of those would reach a host twice.
package enum TapToPayReaderEvent: Sendable, Equatable {
    /// How far a reader configuration has got, as a percentage.
    ///
    /// Configuration runs for minutes on a device arming for the first time,
    /// which is the whole reason this event exists.
    case configurationProgress(percent: Int)

    /// The reader cannot take a card yet.
    case notReady

    /// A card is in the field.
    case cardDetected

    /// The card has been read and should be taken away.
    case cardRemovalRequested

    /// The read did not succeed and the card should be presented again.
    case cardReadRetryRequested

    /// The payer is being asked for a PIN.
    case pinEntryRequested

    /// The payer has finished entering a PIN.
    case pinEntryCompleted

    /// The prompt the platform drew is gone. The read may still resolve.
    case promptDismissed
}

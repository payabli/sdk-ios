import Foundation

/// What a running charge is doing, carried by ``PayabliTTPSessionState/charging(activity:)``.
///
/// Raw values are public API: do not reorder or renumber.
public enum TapToPayChargeActivity: Int, Sendable, CaseIterable {
    /// Opening the payment with Payabli. No card has been asked for yet.
    case opening = 0

    /// The reader is waiting for a card, and the payer can tap.
    case waitingForCard = 1

    /// Telling Payabli how the read ended. The card is no longer needed.
    case closing = 2

    /// A card is in the field.
    case cardDetected = 3

    /// The card has been read and should be taken away.
    case cardRemovalRequested = 4

    /// The read did not succeed and the card should be presented again.
    case cardReadRetryRequested = 5

    /// The payer is being asked for a PIN.
    case pinEntryRequested = 6

    /// The payer has finished entering a PIN.
    case pinEntryCompleted = 7

    /// The prompt the platform drew is gone. The read may still resolve.
    case readerPromptDismissed = 8
}

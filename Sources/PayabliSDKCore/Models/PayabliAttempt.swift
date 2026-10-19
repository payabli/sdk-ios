import Foundation

/// Whether a payment request is a new payment or a retry of one whose outcome is unknown.
///
/// A request is a new payment unless it says otherwise, and a new payment always sends a key of its own. A retry
/// sends the key held for the payment it names, so a service that still recognises the key refuses the repeat. A
/// retry with no key held sends a new one.
@objc public enum PayabliAttempt: Int, Sendable, CaseIterable {
    /// A payment of its own, sent under a new key.
    case newPayment = 0

    /// A repeat of a payment whose outcome is unknown, sent under that payment's key. It describes the same payment,
    /// or it is refused before anything is sent.
    case retry = 1
}

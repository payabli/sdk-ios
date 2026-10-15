import Foundation

/// Whether a payment request is a new payment or a retry of one whose outcome is unknown.
///
/// A request is a new payment unless it says otherwise, and a new payment always sends a key of its own. A retry
/// sends the key of the most recent attempt whose outcome is still unknown, so the service refuses it rather than
/// taking the payment a second time. A retry with no such attempt held sends a new key.
@objc public enum PayabliAttempt: Int, Sendable, CaseIterable {
    /// A payment of its own, sent under a new key.
    case newPayment = 0

    /// A repeat of the most recent attempt whose outcome is unknown, sent under that attempt's key.
    case retry = 1
}

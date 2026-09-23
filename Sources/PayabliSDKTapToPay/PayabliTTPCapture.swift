import Foundation

/// Whether a failed charge took money from the card.
///
/// Only ``notCharged`` means a second attempt cannot take the money twice.
public enum PayabliTTPCapture: Int, Sendable, CaseIterable {
    /// No money moved: the card was never read, or the processor refused it.
    case notCharged = 0

    /// The processor may have taken the sale, and the SDK never learned whether it did.
    case unknown = 1

    /// The processor took the sale.
    case charged = 2
}

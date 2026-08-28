import Foundation

/// A figure drawn per attempt, so a row carries a second signal beyond the
/// customer and the order identifier.
///
/// Drawn independently, so two attempts can land on the same amount: thirteen
/// hundred values, and no memory of the last one. What makes a row attributable
/// is ``QAIdentity`` and the order identifier; the figure narrows a list by eye
/// and is not what a reader should key on.
///
/// Whole cents from $2.00 to $14.99: above the range where a paypoint's own
/// minimum could refuse it, and small enough that a run of them costs nothing.
enum QAAmount {
    private static let minimumCents = 200
    private static let maximumCents = 1499

    /// A `Double` because that is what `PayabliPayInPaymentFlowPaymentDetails`
    /// takes. Drawn in whole cents and divided, rather than drawn as a fraction, so
    /// the figure is one of the 1300 the range actually contains.
    static func random() -> Double {
        Double(Int.random(in: minimumCents ... maximumCents)) / 100
    }
}

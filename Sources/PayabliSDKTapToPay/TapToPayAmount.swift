import Foundation

extension Decimal {
    /// The amount at two places, rounding half to even: the processor's rule, which the reader charges a card at.
    var roundedAsCharged: Decimal {
        var given = self
        var charged = Decimal()
        NSDecimalRound(&charged, &given, 2, .bankers)
        return charged
    }
}

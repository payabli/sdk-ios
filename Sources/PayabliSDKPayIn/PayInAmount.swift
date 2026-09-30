import Foundation

/// An amount as the wire carries it: two decimal places, rounded half up.
enum PayInAmount {
    static let wireFractionDigits = 2

    /// The largest magnitude the wire's decimal type holds at two places.
    static let wireMaximum = Decimal(string: "792281625142643375935439503.35") ?? .greatestFiniteMagnitude

    static func atWireScale(_ value: Decimal) -> Decimal {
        var value = value
        var rounded = Decimal()
        NSDecimalRound(&rounded, &value, wireFractionDigits, .plain)
        return rounded
    }

    /// The amount as it would be sent, or nil when it cannot be sent at all.
    static func sendable(_ value: Double) -> Decimal? {
        // Checked as a Double first: `Decimal(_:)` traps on a non-finite value and is unreliable far past the
        // wire's range.
        guard value.isFinite, abs(value) < 1e28 else { return nil }
        let rounded = atWireScale(Decimal(value))
        guard !rounded.isNaN, abs(rounded) <= wireMaximum else { return nil }
        return rounded
    }

    /// The figure a row shows: nil when the amount is absent, cannot be sent, or is sent as zero.
    static func shown(_ value: Double?) -> Decimal? {
        guard let value, let sent = sendable(value), !sent.isZero else { return nil }
        return sent
    }
}

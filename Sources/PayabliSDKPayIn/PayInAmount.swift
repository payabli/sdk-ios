import Foundation

/// An amount as the wire carries it: two decimal places, a tie rounded away from zero.
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

    /// The amount as sent, or nil when it cannot be sent.
    static func sendable(_ value: Double) -> Decimal? {
        // Checked as a Double first: `Decimal(_:)` traps on a non-finite value.
        guard value.isFinite, abs(value) < 1e28,
              // The shortest decimal that reads back as this Double, so `1.005` is the tie it was written as.
              let exact = Decimal(string: String(value), locale: Locale(identifier: "en_US_POSIX"))
        else { return nil }
        let rounded = atWireScale(exact)
        guard !rounded.isNaN, abs(rounded) <= wireMaximum else { return nil }
        return rounded
    }

    /// The figure a row shows: nil when the amount is absent, cannot be sent, or is sent as zero.
    static func shown(_ value: Double?) -> Decimal? {
        guard let value, let sent = sendable(value), !sent.isZero else { return nil }
        return sent
    }
}

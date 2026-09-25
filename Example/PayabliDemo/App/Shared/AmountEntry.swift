import Foundation

/// An amount a viewer types, written and read in the device's locale, since the decimal keypad
/// offers that locale's separator.
enum AmountEntry {
    static func text(for amount: Double, locale: Locale = .autoupdatingCurrent) -> String {
        amount.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(locale))
    }

    static func amount(from text: String, locale: Locale = .autoupdatingCurrent) -> Double? {
        guard let amount = try? Double(text, format: .number.locale(locale)), amount > 0 else { return nil }
        return amount
    }
}

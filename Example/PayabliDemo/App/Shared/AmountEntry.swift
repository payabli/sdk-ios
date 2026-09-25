import Foundation

/// An amount a viewer types, written and read in the device's locale, since the decimal keypad
/// offers that locale's separator.
enum AmountEntry {
    static func text(for amount: Double, locale: Locale = .autoupdatingCurrent) -> String {
        amount.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(locale))
    }

    /// A positive amount written as digits with at most two decimal places, or nil.
    static func amount(from text: String, locale: Locale = .autoupdatingCurrent) -> Double? {
        let separator = locale.decimalSeparator ?? "."
        let pattern = "^[0-9]+(" + NSRegularExpression.escapedPattern(for: separator) + "[0-9]{1,2})?$"
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        guard trimmed.range(of: pattern, options: .regularExpression) != nil,
              let amount = Double(trimmed.replacingOccurrences(of: separator, with: ".")),
              amount > 0
        else { return nil }
        return amount
    }
}

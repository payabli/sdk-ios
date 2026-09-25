import Foundation

/// An amount a viewer types, written and read in the device's locale, since the decimal keypad
/// offers that locale's separator.
enum AmountEntry {
    static func text(for amount: Double, locale: Locale = .autoupdatingCurrent) -> String {
        amount.formatted(.number.precision(.fractionLength(2)).grouping(.never).locale(locale))
    }

    /// A positive amount written as digits with at most two decimal places, or nil. Digits may be any
    /// script's; the only other character read is the locale's decimal separator.
    static func amount(from text: String, locale: Locale = .autoupdatingCurrent) -> Double? {
        let separator = locale.decimalSeparator ?? "."
        var ascii = ""
        for character in text.trimmingCharacters(in: .whitespaces) {
            if String(character) == separator {
                ascii.append(".")
            } else if let digit = decimalDigit(character) {
                ascii.append(String(digit))
            } else {
                return nil
            }
        }
        guard ascii.range(of: "^[0-9]+(\\.[0-9]{1,2})?$", options: .regularExpression) != nil,
              let amount = Double(ascii),
              amount > 0
        else { return nil }
        return amount
    }

    private static func decimalDigit(_ character: Character) -> Int? {
        guard character.unicodeScalars.count == 1,
              let scalar = character.unicodeScalars.first,
              scalar.properties.generalCategory == .decimalNumber,
              let value = scalar.properties.numericValue
        else { return nil }
        return Int(value)
    }
}

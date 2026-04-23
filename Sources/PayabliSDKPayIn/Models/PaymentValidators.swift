import Foundation

/// Validation rules for payment form fields.
///
/// See PRD §10 "Validation Rules".
public enum PaymentValidators {

    // MARK: - Card number (Luhn)

    /// Validates a card number using the Luhn (mod-10) algorithm.
    /// Requires 13–19 digits (PRD FR-1.4).
    public static func isValidCardNumber(_ input: String) -> Bool {
        let digits = input.filter(\.isNumber)
        guard (13...19).contains(digits.count) else { return false }

        // All-zeros technically passes mod-10 but is obviously not a real PAN.
        guard digits.contains(where: { $0 != "0" }) else { return false }

        var sum = 0
        for (index, char) in digits.reversed().enumerated() {
            guard let digit = char.wholeNumberValue else { return false }
            if index.isMultiple(of: 2) {
                sum += digit
            } else {
                let doubled = digit * 2
                sum += (doubled > 9) ? (doubled - 9) : doubled
            }
        }
        return sum.isMultiple(of: 10)
    }

    // MARK: - Card brand detection (PRD §10)

    public enum CardBrand: String, Sendable {
        case visa = "Visa"
        case mastercard = "Mastercard"
        case amex = "American Express"
        case discover = "Discover"
        case unknown = "Unknown"
    }

    public static func cardBrand(for input: String) -> CardBrand {
        let digits = input.filter(\.isNumber)
        guard !digits.isEmpty else { return .unknown }

        if digits.hasPrefix("4") { return .visa }
        if digits.hasPrefix("37") || digits.hasPrefix("34") { return .amex }
        if digits.hasPrefix("6011") { return .discover }
        if let first = digits.first.flatMap(String.init), "5".contains(first) { return .mastercard }
        // Mastercard also starts with 2221–2720 (post-2016 BINs); not exhaustive.
        if digits.count >= 4, let first4 = Int(digits.prefix(4)), (2221...2720).contains(first4) {
            return .mastercard
        }
        return .unknown
    }

    // MARK: - CVV (PRD FR-1.5)

    public static func isValidCVV(_ input: String, brand: CardBrand) -> Bool {
        let digits = input.filter(\.isNumber)
        let expectedLength = (brand == .amex) ? 4 : 3
        return digits.count == expectedLength
    }

    /// Permissive CVV check: accepts 3 or 4 digits (PRD §10).
    public static func isValidCVV(_ input: String) -> Bool {
        let digits = input.filter(\.isNumber)
        return (3...4).contains(digits.count)
    }

    // MARK: - Expiration date

    /// Validates expiration given month (1–12) and 2- or 4-digit year.
    /// Rejects dates in the past (PRD §10).
    public static func isValidExpiration(month: Int, year: Int, now: Date = Date()) -> Bool {
        guard (1...12).contains(month) else { return false }

        let fullYear: Int
        if year < 100 {
            fullYear = 2000 + year
        } else {
            fullYear = year
        }

        let calendar = Calendar(identifier: .gregorian)
        let todayComponents = calendar.dateComponents([.year, .month], from: now)
        guard let currentYear = todayComponents.year, let currentMonth = todayComponents.month else {
            return false
        }

        if fullYear < currentYear { return false }
        if fullYear == currentYear, month < currentMonth { return false }
        if fullYear > currentYear + 50 { return false } // sanity bound
        return true
    }

    // MARK: - ZIP (PRD §10)

    public static func isValidZIP(_ input: String) -> Bool {
        let digits = input.filter(\.isNumber)
        return digits.count >= 5
    }

    // MARK: - Routing number (PRD §10 — exactly 9 digits + ABA checksum)

    public static func isValidRoutingNumber(_ input: String) -> Bool {
        let digits = input.filter(\.isNumber)
        guard digits.count == 9 else { return false }
        let numbers = digits.compactMap(\.wholeNumberValue)
        guard numbers.count == 9 else { return false }

        let checksum = (
            3 * (numbers[0] + numbers[3] + numbers[6])
            + 7 * (numbers[1] + numbers[4] + numbers[7])
            + (numbers[2] + numbers[5] + numbers[8])
        )
        return checksum.isMultiple(of: 10)
    }

    // MARK: - Account number (PRD §10)

    public static func isValidAccountNumber(_ input: String) -> Bool {
        let digits = input.filter(\.isNumber)
        return digits.count >= 4
    }

    // MARK: - Name (non-empty)

    public static func isValidHolderName(_ input: String) -> Bool {
        !input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

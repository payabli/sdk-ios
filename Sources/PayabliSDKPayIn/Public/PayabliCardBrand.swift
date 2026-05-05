import Foundation

/// Set of card brands a `CardFormView` will accept.
///
/// Pass to `CardFormView(allowedBrands:)` (or the `.payabliCardSheet`
/// modifiers) to restrict which networks the form will tokenize. The brand
/// preview row hides disallowed badges, and entering a PAN whose detected
/// brand is not in the set surfaces an inline validation error
/// (`CardFormStrings.disallowedBrandError`).
///
/// `.unknown` brands (PAN too short to detect) are never blocked — only
/// concretely-detected brands are checked against the set.
///
/// ```swift
/// CardFormView(
///     customerId: 4440,
///     allowedBrands: [.visa, .mastercard]  // no Amex, no Discover
/// ) { token, error in /* ... */ }
/// ```
public struct PayabliCardBrand: OptionSet, Sendable, Hashable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let visa       = PayabliCardBrand(rawValue: 1 << 0)
    public static let mastercard = PayabliCardBrand(rawValue: 1 << 1)
    public static let amex       = PayabliCardBrand(rawValue: 1 << 2)
    public static let discover   = PayabliCardBrand(rawValue: 1 << 3)

    /// All four major brands — the default used by `CardFormView`.
    public static let all: PayabliCardBrand = [.visa, .mastercard, .amex, .discover]

    /// Whether a concretely-detected brand is allowed by this set.
    ///
    /// `.unknown` always returns `true` — the form does not block input while
    /// the BIN is still being entered.
    public func allows(_ brand: PaymentValidators.CardBrand) -> Bool {
        switch brand {
        case .visa:       return contains(.visa)
        case .mastercard: return contains(.mastercard)
        case .amex:       return contains(.amex)
        case .discover:   return contains(.discover)
        case .unknown:    return true
        }
    }
}

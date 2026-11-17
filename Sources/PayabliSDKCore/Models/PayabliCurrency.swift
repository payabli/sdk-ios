import Foundation

/// A currency a payment can be made in. Raw values are public API: do not reorder or renumber.
@objc public enum PayabliCurrency: Int, Sendable, CaseIterable {
    /// United States dollars.
    case usd = 0

    /// The ISO 4217 code the service receives for this currency, such as `"USD"`.
    public var code: String {
        switch self {
        case .usd: "USD"
        }
    }
}

package extension PayabliCurrency? {
    /// The currency a payment is sent in: the one named, or USD when none is.
    var asSent: PayabliCurrency {
        self ?? .usd
    }
}

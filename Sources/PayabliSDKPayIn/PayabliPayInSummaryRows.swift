import Foundation

/// The rows the payment summary draws, read one at a time by a host that draws its own summary.
public enum PayabliPayInSummaryRows {
    public static func labelText(
        for field: PayabliPayInField,
        labels: PayabliPayInFormLabels
    ) -> String {
        labels.label(for: field)
    }

    public static func totalLabelText(labels: PayabliPayInFormLabels) -> String {
        labels.total?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty ?? "Total"
    }

    /// The figure a money row shows, at the two places it is sent, or nil when the form draws no row for it.
    ///
    /// Amount is the total amount less the service fee and any surcharge sent, and has a figure only while a fee or
    /// a surcharge sits beside it. Every row is nil while submit would refuse the payment details.
    ///
    /// - Parameter field: the money field whose figure the row shows; any other field draws no row.
    /// - Parameter paymentDetails: the payment's amounts, at the precision the request carries them.
    /// - Returns: the figure the row shows, or nil when there is none to show.
    public static func rowAmount(for field: PayabliPayInField, paymentDetails: PayabliPayInPaymentDetails?) -> Decimal? {
        guard let paymentDetails, areValid(paymentDetails) else { return nil }
        let fee = PayInAmount.shown(paymentDetails.serviceFee)
        let surcharge = PayInAmount.shown(paymentDetails.surchargeFee)
        switch field {
        case .amount:
            guard fee != nil || surcharge != nil,
                  let charge = PayInAmount.shown(paymentDetails.totalAmount)
            else { return nil }
            let base = charge - (fee ?? 0) - (surcharge ?? 0)
            return base.isZero ? nil : base
        case .serviceFee:
            return fee
        case .surchargeFee:
            return surcharge
        default:
            return nil
        }
    }

    /// What the service charges, the total amount, which already holds any surcharge sent, or nil when submit would
    /// refuse the payment details.
    ///
    /// - Parameter paymentDetails: the payment's amounts, from which the charge is read.
    /// - Returns: the charge the Total row shows, or nil when there is none.
    public static func totalRowAmount(paymentDetails: PayabliPayInPaymentDetails?) -> Decimal? {
        guard let paymentDetails, areValid(paymentDetails) else { return nil }
        return PayInAmount.shown(paymentDetails.totalAmount)
    }

    /// A figure as the form writes it: the device locale's separators, the currency's symbol, two places.
    ///
    /// A currency that is absent or not an ISO 4217 code writes the number alone, since the charge is then made
    /// in a currency the request does not name.
    ///
    /// - Parameter amount: the figure to write, rounded here to the wire's two places.
    /// - Parameter currency: the charge's ISO 4217 code, which names the symbol; absent or not a code writes
    ///   the figure without one.
    /// - Returns: the figure as text, in the device locale's separators.
    public static func formattedAmount(_ amount: Decimal, currency: String?) -> String {
        formattedAmount(amount, currency: currency, locale: .current)
    }

    static func formattedAmount(_ amount: Decimal, currency: String?, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        let code = currency?.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if let code, isoCurrencyCodes.contains(code) {
            formatter.numberStyle = .currency
            formatter.currencyCode = code
        } else {
            formatter.numberStyle = .decimal
        }
        // The two places the wire carries, whatever the currency's own convention, so the text is the figure sent.
        formatter.minimumFractionDigits = PayInAmount.wireFractionDigits
        formatter.maximumFractionDigits = PayInAmount.wireFractionDigits
        formatter.roundingMode = .halfUp
        let sent = PayInAmount.atWireScale(amount)
        return formatter.string(from: NSDecimalNumber(decimal: sent)) ?? "\(sent)"
    }

    private static func areValid(_ paymentDetails: PayabliPayInPaymentDetails) -> Bool {
        (try? paymentDetails.validate()) != nil
    }

    private static let isoCurrencyCodes = Set(Locale.Currency.isoCurrencies.map(\.identifier))
}

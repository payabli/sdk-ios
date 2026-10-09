import Foundation

/// The rows the payment summary draws, read one at a time by a host that draws its own summary.
public enum PayabliPayInSummaryRows {
    public static func labelText(
        for field: PayabliPayInField,
        labels: PayabliPayInLabels
    ) -> String {
        labels.label(for: field)
    }

    public static func totalLabelText(labels: PayabliPayInLabels) -> String {
        labels.total?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty ?? "Total"
    }

    /// The figure a money row shows, at the two places it is sent, or nil when the form draws no row for it.
    ///
    /// Amount is the total amount less the service fee, and has a figure only while a fee or a surcharge sits
    /// beside it. Every row is nil while submit would refuse the payment details.
    public static func rowAmount(for field: PayabliPayInField, paymentDetails: PayabliPayInPaymentDetails?) -> Decimal? {
        guard let paymentDetails, areValid(paymentDetails) else { return nil }
        let fee = PayInAmount.shown(paymentDetails.serviceFee)
        let surcharge = PayInAmount.shown(paymentDetails.surchargeFee)
        switch field {
        case .amount:
            guard fee != nil || surcharge != nil,
                  let charge = PayInAmount.shown(paymentDetails.totalAmount)
            else { return nil }
            let base = charge - (fee ?? 0)
            return base.isZero ? nil : base
        case .serviceFee:
            return fee
        case .surchargeFee:
            return surcharge
        default:
            return nil
        }
    }

    /// What the service charges, the total amount plus any surcharge, or nil when that is nothing or when submit
    /// would refuse the payment details.
    public static func totalRowAmount(paymentDetails: PayabliPayInPaymentDetails?) -> Decimal? {
        guard let paymentDetails, areValid(paymentDetails),
              let charge = PayInAmount.shown(paymentDetails.totalAmount)
        else { return nil }
        let total = charge + (PayInAmount.shown(paymentDetails.surchargeFee) ?? 0)
        return total.isZero ? nil : total
    }

    /// A figure as the form writes it: the device locale's separators, the currency's symbol, two places.
    ///
    /// A currency that is absent or not an ISO 4217 code writes the number alone, since the charge is then made
    /// in a currency the request does not name.
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

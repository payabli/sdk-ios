import Foundation

/// The payment a held key was sent for, so a declared retry goes out under that key only for the same payment. Kept in
/// memory beside the key and dropped with it; it names an amount, so it never prints its fields.
struct ChargeDescription: CustomStringConvertible {
    private let amount: Decimal
    private let serviceFee: Decimal
    private let currency: String?
    private let invoiceNumber: String?

    /// - Parameter paymentDetails: the amounts and currency the charge sends, already normalised.
    /// - Parameter invoice: the invoice the charge names, its number already trimmed.
    init(paymentDetails: PayabliTTPPaymentDetails, invoice: PayabliTTPInvoiceData) {
        amount = paymentDetails.amount
        serviceFee = paymentDetails.serviceFee
        currency = paymentDetails.currency
        invoiceNumber = invoice.invoiceNumber
    }

    var description: String {
        "ChargeDescription(redacted)"
    }

    /// Whether a retry describing `retry` repeats this payment.
    ///
    /// - Parameter retry: the payment the retry describes.
    /// - Returns: whether every compared field agrees; an invoice number counts only when this payment set one.
    func isRepeated(by retry: Self) -> Bool {
        amount == retry.amount
            && serviceFee == retry.serviceFee
            && currency == retry.currency
            && (invoiceNumber == nil || invoiceNumber == retry.invoiceNumber)
    }
}

import Foundation

// MARK: - Card read request / result (PRD §7.2 Models — FR-11A.2, FR-11A.3)

/// Parameters the facade hands to the provider for an NFC charge. Atomic
/// providers (Fiserv) forward the merchant IDs to their processor SDK so the
/// charge can be correlated with the Payabli `paymentTransId`.
public struct CardReadRequest: Sendable {
    public let amount: Decimal
    /// Payabli-generated `paymentTransId` from `/initiate`. Sent to the
    /// processor SDK as its primary merchant-side correlation identifier.
    public let merchantTransactionId: String
    public let merchantOrderId: String?
    public let merchantInvoiceNumber: String?
    /// Structured customer data as provided to `PayabliTTP.charge(..., customer:)`.
    /// Never `nil` — an empty `PayabliTTPCustomerData` is passed when the host
    /// app did not supply customer information, so adapters can always rely on
    /// a concrete value type.
    public let customer: PayabliTTPCustomerData
    /// Structured order data as provided to `PayabliTTP.charge(..., order:)`.
    public let order: PayabliTTPOrderData

    public init(
        amount: Decimal,
        merchantTransactionId: String,
        merchantOrderId: String? = nil,
        merchantInvoiceNumber: String? = nil,
        customer: PayabliTTPCustomerData = PayabliTTPCustomerData(),
        order: PayabliTTPOrderData = PayabliTTPOrderData()
    ) {
        self.amount = amount
        self.merchantTransactionId = merchantTransactionId
        self.merchantOrderId = merchantOrderId
        self.merchantInvoiceNumber = merchantInvoiceNumber
        self.customer = customer
        self.order = order
    }
}

/// Provider-agnostic encrypted card-read result (PRD FR-11A.3).
public struct CardReadResult: Sendable {
    /// Provider identifier — see `TapToPayProvider.providerId`.
    public let provider: String

    /// Encrypted payload the backend forwards to the processor. Used by
    /// providers that follow a "collect then charge" flow. For atomic providers
    /// (Fiserv) this is empty and the full response lives in
    /// `providerResponseJSON`.
    public let encryptedPayload: Data

    /// Detected card network, when the provider can surface it.
    public let cardNetwork: String?

    /// Additional provider-specific string metadata (forwarded as-is to the API).
    public let providerMetadata: [String: String]

    /// Full provider charge response, encoded as JSON. Forwarded verbatim to
    /// `PATCH /api/v2/MoneyIn/update/{id}` under the `fiservResponse` key.
    /// `nil` when the provider does not return a processor response at the SDK
    /// layer (payload-only providers).
    public let providerResponseJSON: Data?

    public init(
        provider: String,
        encryptedPayload: Data,
        cardNetwork: String? = nil,
        providerMetadata: [String: String] = [:],
        providerResponseJSON: Data? = nil
    ) {
        self.provider = provider
        self.encryptedPayload = encryptedPayload
        self.cardNetwork = cardNetwork
        self.providerMetadata = providerMetadata
        self.providerResponseJSON = providerResponseJSON
    }
}

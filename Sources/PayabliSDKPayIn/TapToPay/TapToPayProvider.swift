import Foundation

/// Provider-agnostic abstraction over the contactless NFC card reader.
///
/// Implementations (Fiserv, Stripe, Apple ProximityReader direct, etc.) are
/// registered with `TapToPayProviderFactory`. The TTP facade depends only on
/// this protocol (PRD FR-11A.1..7).
///
/// v1.0 only ships the Fiserv adapter. Because FiservTTP's `charges(amount:)`
/// is atomic (NFC read + charge in a single SDK call), `startReading` receives
/// a `CardReadRequest` (amount + merchant correlation IDs) and returns a
/// `CardReadResult` that carries the full processor response JSON under
/// `providerResponseJSON`. Future providers that follow a "collect encrypted
/// payload, charge server-side" flow can ignore the merchant IDs and populate
/// `encryptedPayload` instead.
public protocol TapToPayProvider: AnyObject, Sendable {
    /// Identifier sent in the API payload `provider` field so the backend
    /// routes decryption correctly (PRD FR-11J.3).
    static var providerId: String { get }

    /// Validates that the device + OS + entitlements are acceptable.
    /// Called before any UI is presented (PRD FR-11J.2).
    ///
    /// Implementations must NOT require runtime credentials to be injected
    /// yet: eligibility runs before `/config` returns them. Only validate
    /// platform / hardware / entitlements here.
    func checkEligibility() async -> Result<Void, PayabliTTPError>

    /// Applies the provider-specific credentials block returned by
    /// `/api/v2/device/taptopay/config/{entry}` (PRD FR-11B.3). The facade is
    /// provider-agnostic — it forwards the raw dictionary as received from the
    /// backend and the adapter is responsible for validating and converting
    /// the keys it cares about.
    ///
    /// Must throw `PayabliTTPError.readerSetupFailed(reason:)` (or any other
    /// `PayabliTTPError`) when required keys are missing or malformed so the
    /// initialization fails loudly before `prepareReader()` is attempted.
    ///
    /// Credentials must live only in RAM (NFR-5D); implementations must clear
    /// them in `cleanUp()`.
    func configure(credentials: [String: String]) throws

    /// Prepares the reader (connect, link account, open session).
    /// `configure(credentials:)` must have succeeded before this call.
    func prepareReader() async throws

    /// Runs the NFC interaction and (for atomic providers like Fiserv) the
    /// actual charge. Providers that only collect card data should ignore the
    /// merchant correlation IDs and populate `encryptedPayload` in the result.
    func startReading(_ request: CardReadRequest) async throws -> CardReadResult

    /// Cancels an active reader session.
    func cancelReading() async

    /// Cleans up reader resources.
    func cleanUp() async
}

/// Parameters the facade hands to the provider for an NFC charge. Atomic
/// providers (Fiserv) forward the merchant IDs to their processor SDK so the
/// charge can be correlated with the Payabli `paymentTransId`.
///
/// `customer` and `order` carry the same structured data that was forwarded to
/// `/initiate`, so adapters that can attach a cardholder name or an order id
/// to their processor SDK receive a ready-to-use snapshot. Adapters that have
/// no use for these fields (e.g. Fiserv `charges(amount:)` which does not
/// accept a billing address) may ignore them — the facade still logs them for
/// diagnostics.
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

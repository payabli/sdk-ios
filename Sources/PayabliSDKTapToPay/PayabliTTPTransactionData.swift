import Foundation

// MARK: - Customer data

/// Customer information associated with a Tap to Pay charge.
///
/// The same struct flows transparently across all four stages of the charge
/// pipeline — the host app provides it once to `PayabliTTP.charge(...)` and the
/// SDK threads it through:
///
///   1. `POST /api/v2/MoneyIn/initiate` — serialised as `customerData.firstName
///      / lastName / customerNumber` (PRD §8.2 "Initiate request").
///   2. Provider `startReading(_:)` — forwarded via `CardReadRequest.customer`
///      so adapters that can pass a cardholder name to their processor SDK
///      (e.g. `BillingDetails`) receive it. Fiserv's atomic
///      `charges(amount:)` call does not accept a billing address, so the
///      Fiserv adapter only logs it — but the data is still available to any
///      future provider that needs it.
///   3. `PATCH /api/v2/MoneyIn/update/{id}` — the backend persists the customer
///      from the initiate step, so update bodies only carry the provider
///      response verbatim. Customer data is still available in the SDK
///      transaction context for any host-app observers listening on `events()`.
///
/// All fields are optional; an empty instance is equivalent to "no customer
/// provided" and the backend will accept it as an anonymous payor.
public struct PayabliTTPCustomerData: Sendable, Equatable {
    public let firstName: String?
    public let lastName: String?
    public let customerNumber: String?
    public let email: String?
    public let phone: String?

    public let customerId: Int?
    public let company: String?

    public let billingAddress1: String?
    public let billingAddress2: String?
    public let billingCity: String?
    public let billingState: String?
    public let billingZip: String?
    public let billingCountry: String?
    public let billingPhone: String?
    public let billingEmail: String?

    public let shippingAddress1: String?
    public let shippingAddress2: String?
    public let shippingCity: String?
    public let shippingState: String?
    public let shippingZip: String?
    public let shippingCountry: String?

    public init(
        firstName: String? = nil,
        lastName: String? = nil,
        customerNumber: String? = nil,
        email: String? = nil,
        phone: String? = nil,
        customerId: Int? = nil,
        company: String? = nil,
        billingAddress1: String? = nil,
        billingAddress2: String? = nil,
        billingCity: String? = nil,
        billingState: String? = nil,
        billingZip: String? = nil,
        billingCountry: String? = nil,
        billingPhone: String? = nil,
        billingEmail: String? = nil,
        shippingAddress1: String? = nil,
        shippingAddress2: String? = nil,
        shippingCity: String? = nil,
        shippingState: String? = nil,
        shippingZip: String? = nil,
        shippingCountry: String? = nil
    ) {
        self.firstName = PayabliTTPCustomerData.sanitize(firstName)
        self.lastName = PayabliTTPCustomerData.sanitize(lastName)
        self.customerNumber = PayabliTTPCustomerData.sanitize(customerNumber)
        self.email = PayabliTTPCustomerData.sanitize(email)
        self.phone = PayabliTTPCustomerData.sanitize(phone)
        self.customerId = customerId
        self.company = PayabliTTPCustomerData.sanitize(company)
        self.billingAddress1 = PayabliTTPCustomerData.sanitize(billingAddress1)
        self.billingAddress2 = PayabliTTPCustomerData.sanitize(billingAddress2)
        self.billingCity = PayabliTTPCustomerData.sanitize(billingCity)
        self.billingState = PayabliTTPCustomerData.sanitize(billingState)
        self.billingZip = PayabliTTPCustomerData.sanitize(billingZip)
        self.billingCountry = PayabliTTPCustomerData.sanitize(billingCountry)
        self.billingPhone = PayabliTTPCustomerData.sanitize(billingPhone)
        self.billingEmail = PayabliTTPCustomerData.sanitize(billingEmail)
        self.shippingAddress1 = PayabliTTPCustomerData.sanitize(shippingAddress1)
        self.shippingAddress2 = PayabliTTPCustomerData.sanitize(shippingAddress2)
        self.shippingCity = PayabliTTPCustomerData.sanitize(shippingCity)
        self.shippingState = PayabliTTPCustomerData.sanitize(shippingState)
        self.shippingZip = PayabliTTPCustomerData.sanitize(shippingZip)
        self.shippingCountry = PayabliTTPCustomerData.sanitize(shippingCountry)
    }

    /// True when every field is nil — a signal to adapters / wire serializers
    /// that no customer data was provided.
    public var isEmpty: Bool {
        firstName == nil && lastName == nil && customerNumber == nil
            && email == nil && phone == nil
            && customerId == nil && company == nil
            && billingAddress1 == nil && billingAddress2 == nil
            && billingCity == nil && billingState == nil
            && billingZip == nil && billingCountry == nil
            && billingPhone == nil && billingEmail == nil
            && shippingAddress1 == nil && shippingAddress2 == nil
            && shippingCity == nil && shippingState == nil
            && shippingZip == nil && shippingCountry == nil
    }

    /// Convenience: `"firstName lastName"` with graceful handling of nil sides.
    public var fullName: String {
        [firstName, lastName]
            .compactMap { $0 }
            .joined(separator: " ")
    }

    private static func sanitize(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Order data

/// Order / invoice information associated with a Tap to Pay charge.
///
/// Flows through the same pipeline as `PayabliTTPCustomerData`:
///
///   1. `/initiate` uses `orderId` and `orderDescription` as-is (empty string
///      when nil, matching the reference flow in `SaleView.processSale`).
///   2. `CardReadRequest.order` forwards the struct to the provider adapter,
///      which maps `orderId` → `merchantOrderId` and `invoiceNumber` (falling
///      back to `orderId`) → `merchantInvoiceNumber` on its processor SDK.
///   3. Backend `/update` looks up the transaction by `paymentTransId` — the
///      order metadata persisted at `/initiate` is reused transparently.
public struct PayabliTTPOrderData: Sendable, Equatable {
    public let orderId: String?
    public let orderDescription: String?
    public let invoiceNumber: String?

    public init(
        orderId: String? = nil,
        orderDescription: String? = nil,
        invoiceNumber: String? = nil
    ) {
        self.orderId = PayabliTTPOrderData.sanitize(orderId)
        self.orderDescription = PayabliTTPOrderData.sanitize(orderDescription)
        self.invoiceNumber = PayabliTTPOrderData.sanitize(invoiceNumber)
    }

    public var isEmpty: Bool {
        orderId == nil && orderDescription == nil && invoiceNumber == nil
    }

    private static func sanitize(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Payment details

/// Payment-amount inputs for a Tap to Pay charge. Mirrors the wire-level
/// `paymentDetails` object the backend `/initiate` endpoint expects.
///
/// Threaded through every stage of the charge pipeline:
///   1. `POST /api/v2/MoneyIn/initiate` — serialised as
///      `paymentDetails.{totalAmount, serviceFee, currency, paymentDescription}`.
///   2. Provider `startReading(_:)` — `amount` flows in via
///      `CardReadRequest.amount`. The remaining fields are not consumed by
///      atomic providers (Fiserv) but are available to future providers.
///   3. `PATCH /api/v2/MoneyIn/update/{id}` — backend persists `paymentDetails`
///      from the initiate step; update bodies only carry the provider response.
public struct PayabliTTPPaymentDetails: Sendable, Equatable {
    public let amount: Decimal
    public let serviceFee: Decimal
    public let currency: String
    public let paymentDescription: String?

    public init(
        amount: Decimal,
        serviceFee: Decimal = 0,
        currency: String = "USD",
        paymentDescription: String? = nil
    ) {
        self.amount = amount
        self.serviceFee = serviceFee
        self.currency = PayabliTTPPaymentDetails.normalizeCurrency(currency)
        self.paymentDescription = PayabliTTPPaymentDetails.sanitize(paymentDescription)
    }

    private static func normalizeCurrency(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        let normalized = trimmed.isEmpty ? "USD" : trimmed.uppercased()
        return normalized
    }

    private static func sanitize(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Invoice data

/// Invoice information associated with a Tap to Pay charge. Mirrors the
/// wire-level `invoiceData` object the backend `/initiate` endpoint expects.
///
/// The struct deliberately exposes only `invoiceNumber` — additional invoice
/// metadata (line items, totals, due dates) is not part of the
/// `GetPaidRequestPayload` contract.
public struct PayabliTTPInvoiceData: Sendable, Equatable {
    public let invoiceNumber: String?

    public init(invoiceNumber: String? = nil) {
        self.invoiceNumber = PayabliTTPInvoiceData.sanitize(invoiceNumber)
    }

    public var isEmpty: Bool { invoiceNumber == nil }

    private static func sanitize(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

// MARK: - Internal transaction context

/// Bundles the immutable per-charge inputs (amount, serviceFee, customer,
/// order) so they can be threaded through the 3-step pipeline without
/// exploding argument lists. Lives at the SDK boundary — never exposed to
/// host apps, never persisted.
struct TTPTransactionContext: Sendable {
    let amount: Decimal
    let serviceFee: Decimal
    let customer: PayabliTTPCustomerData
    let order: PayabliTTPOrderData
}

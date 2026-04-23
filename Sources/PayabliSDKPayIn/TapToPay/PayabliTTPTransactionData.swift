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
///      (e.g. Stripe `BillingDetails`) receive it. Fiserv's atomic
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

    public init(
        firstName: String? = nil,
        lastName: String? = nil,
        customerNumber: String? = nil,
        email: String? = nil,
        phone: String? = nil
    ) {
        self.firstName = PayabliTTPCustomerData.sanitize(firstName)
        self.lastName = PayabliTTPCustomerData.sanitize(lastName)
        self.customerNumber = PayabliTTPCustomerData.sanitize(customerNumber)
        self.email = PayabliTTPCustomerData.sanitize(email)
        self.phone = PayabliTTPCustomerData.sanitize(phone)
    }

    /// True when every field is nil or blank — a signal to adapters that no
    /// customer was provided and they should fall back to provider defaults.
    public var isEmpty: Bool {
        firstName == nil && lastName == nil && customerNumber == nil
            && email == nil && phone == nil
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

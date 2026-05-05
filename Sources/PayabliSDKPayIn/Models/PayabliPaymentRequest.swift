import Foundation

/// Indicates who initiated a transaction (PRD FR-12A.7, FR-12B.4).
@objc public enum PaymentInitiator: Int, Sendable {
    case payor = 0
    case merchant = 1

    var apiValue: String {
        self == .payor ? "payor" : "merchant"
    }
}

/// Stored-method usage type for MIT compliance (PRD FR-12B.3).
@objc public enum StoredMethodUsageType: Int, Sendable {
    case unscheduled = 0
    case subscription = 1
    case recurring = 2

    var apiValue: String {
        switch self {
        case .unscheduled: return "unscheduled"
        case .subscription: return "subscription"
        case .recurring: return "recurring"
        }
    }
}

/// Optional invoice metadata attached to a transaction.
/// The SDK forwards this as-is; business validation is the backend's responsibility (FR-12D.3).
public struct PayabliInvoiceData: Encodable, Sendable {
    public let invoiceNumber: String?
    public let invoiceDate: String?
    public let invoiceDueDate: String?
    public let subtotal: Decimal?
    public let tax: Decimal?
    public let discount: Decimal?

    public init(
        invoiceNumber: String? = nil,
        invoiceDate: String? = nil,
        invoiceDueDate: String? = nil,
        subtotal: Decimal? = nil,
        tax: Decimal? = nil,
        discount: Decimal? = nil
    ) {
        self.invoiceNumber = invoiceNumber
        self.invoiceDate = invoiceDate
        self.invoiceDueDate = invoiceDueDate
        self.subtotal = subtotal
        self.tax = tax
        self.discount = discount
    }
}

/// Payment line-item category (PRD FR-12D.2).
public struct PayabliCategory: Encodable, Sendable {
    public let label: String
    public let amount: Decimal
    public let quantity: Int?

    public init(label: String, amount: Decimal, quantity: Int? = nil) {
        self.label = label
        self.amount = amount
        self.quantity = quantity
    }
}

/// Input to `PayabliPayIn.processPayment(...)` and `chargeStoredMethod(...)`.
///
/// See PRD FR-12A, FR-12B.
public struct PayabliPaymentRequest: Sendable {
    /// Total amount to charge.
    public let totalAmount: Decimal

    /// Optional service fee surcharge.
    public let serviceFee: Decimal

    /// ISO 4217 currency code. Default `"USD"`.
    public let currency: String

    public let orderId: String?
    public let orderDescription: String?

    /// If `true` and the payment is approved, the backend stores the payment method
    /// and returns a `methodReferenceId` the host app can reuse (FR-12C.6).
    public let saveIfSuccess: Bool

    /// Idempotency key. If `nil`, the SDK generates a UUID (FR-12A.6).
    public let idempotencyKey: String?

    public let invoiceData: PayabliInvoiceData?
    public let categories: [PayabliCategory]?

    /// Stored method reference for headless payments (FR-12B.1).
    public let storedMethodId: String?
    public let storedMethodUsageType: StoredMethodUsageType?

    /// Override for the `initiator` field. Defaults: `.payor` for form flows,
    /// `.merchant` for stored-method flows.
    public let initiator: PaymentInitiator?

    public init(
        totalAmount: Decimal,
        serviceFee: Decimal = 0,
        currency: String = "USD",
        orderId: String? = nil,
        orderDescription: String? = nil,
        saveIfSuccess: Bool = false,
        idempotencyKey: String? = nil,
        invoiceData: PayabliInvoiceData? = nil,
        categories: [PayabliCategory]? = nil,
        storedMethodId: String? = nil,
        storedMethodUsageType: StoredMethodUsageType? = nil,
        initiator: PaymentInitiator? = nil
    ) {
        self.totalAmount = totalAmount
        self.serviceFee = serviceFee
        self.currency = currency
        self.orderId = orderId
        self.orderDescription = orderDescription
        self.saveIfSuccess = saveIfSuccess
        self.idempotencyKey = idempotencyKey
        self.invoiceData = invoiceData
        self.categories = categories
        self.storedMethodId = storedMethodId
        self.storedMethodUsageType = storedMethodUsageType
        self.initiator = initiator
    }
}

import Foundation

// MARK: - ObjC companions for transaction-data structs
//
// These `*ObjC` classes are thin wrappers around the Swift value types in
// `PayabliTTPTransactionData.swift` / `PayabliTTPTypes.swift` so ObjC, MAUI
// (sharpie), Flutter, and React Native consumers can build the same payloads
// that Swift callers express as `struct`s. Each class exposes immutable
// `@objc` properties and an `init(...)` mirroring the Swift parameter labels;
// the internal `toSwift()` / `init(_:)` helpers bridge to and from the
// underlying `Sendable` value type.
//
// Maintenance contract: any change to a public field on the Swift struct
// MUST be reflected here at the same time. The `*ObjC` classes are part of
// the public API.

/// ObjC companion for `PayabliTTPCustomerData`.
///
/// All fields are optional and mirror the Swift struct's parameter labels
/// exactly. Pass `nil` for fields that don't apply — the SDK threads the
/// resulting struct through the charge pipeline the same way as a Swift-
/// constructed value.
@objc(PayabliTTPCustomerDataObjC)
public final class PayabliTTPCustomerDataObjC: NSObject {
    @objc public let firstName: String?
    @objc public let lastName: String?
    @objc public let customerNumber: String?
    @objc public let email: String?
    @objc public let phone: String?

    /// Designated init. Argument labels match `PayabliTTPCustomerData.init`.
    @objc public init(
        firstName: String?,
        lastName: String?,
        customerNumber: String?,
        email: String?,
        phone: String?
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.customerNumber = customerNumber
        self.email = email
        self.phone = phone
        super.init()
    }

    /// Bridge to the Swift value type used internally by the charge pipeline.
    func toSwift() -> PayabliTTPCustomerData {
        PayabliTTPCustomerData(
            firstName: firstName,
            lastName: lastName,
            customerNumber: customerNumber,
            email: email,
            phone: phone
        )
    }
}

/// ObjC companion for `PayabliTTPOrderData`.
///
/// Same shape as `PayabliTTPCustomerDataObjC`: ordered, optional fields with
/// labels that mirror the Swift struct.
@objc(PayabliTTPOrderDataObjC)
public final class PayabliTTPOrderDataObjC: NSObject {
    @objc public let orderId: String?
    @objc public let orderDescription: String?
    @objc public let invoiceNumber: String?

    /// Designated init. Argument labels match `PayabliTTPOrderData.init`.
    @objc public init(
        orderId: String?,
        orderDescription: String?,
        invoiceNumber: String?
    ) {
        self.orderId = orderId
        self.orderDescription = orderDescription
        self.invoiceNumber = invoiceNumber
        super.init()
    }

    /// Bridge to the Swift value type used internally by the charge pipeline.
    func toSwift() -> PayabliTTPOrderData {
        PayabliTTPOrderData(
            orderId: orderId,
            orderDescription: orderDescription,
            invoiceNumber: invoiceNumber
        )
    }
}

/// ObjC companion for `TransactionResult`.
///
/// Returned to ObjC callers via the `charge(amount:type:serviceFee:customer:order:completion:)`
/// completion block when the underlying Swift `charge(...)` returns
/// successfully.
@objc(PayabliTTPTransactionResultObjC)
public final class PayabliTTPTransactionResultObjC: NSObject {
    @objc public let paymentTransId: String

    /// Bridge from the Swift value type returned by the charge pipeline.
    init(_ result: TransactionResult) {
        self.paymentTransId = result.paymentTransId
        super.init()
    }
}

/// ObjC companion for `PayabliTTPPaymentDetails`.
///
/// `amount` and `serviceFee` use `NSDecimalNumber` for lossless bridging to
/// Swift `Decimal`. `currency` is non-null on the ObjC side because the Swift
/// struct always materializes a non-nil currency (default `"USD"`).
@objc(PayabliTTPPaymentDetailsObjC)
public final class PayabliTTPPaymentDetailsObjC: NSObject {
    @objc public let amount: NSDecimalNumber
    @objc public let serviceFee: NSDecimalNumber
    @objc public let currency: String
    @objc public let paymentDescription: String?

    @objc public init(
        amount: NSDecimalNumber,
        serviceFee: NSDecimalNumber,
        currency: String,
        paymentDescription: String?
    ) {
        self.amount = amount
        self.serviceFee = serviceFee
        self.currency = currency
        self.paymentDescription = paymentDescription
        super.init()
    }

    func toSwift() -> PayabliTTPPaymentDetails {
        PayabliTTPPaymentDetails(
            amount: amount.decimalValue,
            serviceFee: serviceFee.decimalValue,
            currency: currency,
            paymentDescription: paymentDescription
        )
    }
}

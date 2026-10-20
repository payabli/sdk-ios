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

    @objc public let customerId: NSNumber?
    @objc public let company: String?

    @objc public let billingAddress1: String?
    @objc public let billingAddress2: String?
    @objc public let billingCity: String?
    @objc public let billingState: String?
    @objc public let billingZip: String?
    @objc public let billingCountry: String?
    @objc public let billingPhone: String?
    @objc public let billingEmail: String?

    @objc public let shippingAddress1: String?
    @objc public let shippingAddress2: String?
    @objc public let shippingCity: String?
    @objc public let shippingState: String?
    @objc public let shippingZip: String?
    @objc public let shippingCountry: String?

    /// Designated init. Argument labels match `PayabliTTPCustomerData.init`.
    ///
    /// - Parameters:
    ///   - firstName: the customer's first name, or `nil` when none is given.
    ///   - lastName: the customer's last name, or `nil` when none is given.
    ///   - customerNumber: the merchant's own number for the customer.
    ///   - email: the customer's email address, or `nil` when none is given.
    ///   - phone: the customer's phone number, or `nil` when none is given.
    ///   - customerId: the merchant's numeric id for the customer.
    ///   - company: the customer's company name, or `nil` when none is given.
    ///   - billingAddress1: the billing street address, first line.
    ///   - billingAddress2: the billing street address, second line.
    ///   - billingCity: the billing address's city.
    ///   - billingState: the billing address's state.
    ///   - billingZip: the billing address's postal code.
    ///   - billingCountry: the billing address's country.
    ///   - billingPhone: the billing contact's phone number.
    ///   - billingEmail: the billing contact's email address.
    ///   - shippingAddress1: the shipping street address, first line.
    ///   - shippingAddress2: the shipping street address, second line.
    ///   - shippingCity: the shipping address's city.
    ///   - shippingState: the shipping address's state.
    ///   - shippingZip: the shipping address's postal code.
    ///   - shippingCountry: the shipping address's country.
    @objc public init(
        firstName: String?,
        lastName: String?,
        customerNumber: String?,
        email: String?,
        phone: String?,
        customerId: NSNumber?,
        company: String?,
        billingAddress1: String?,
        billingAddress2: String?,
        billingCity: String?,
        billingState: String?,
        billingZip: String?,
        billingCountry: String?,
        billingPhone: String?,
        billingEmail: String?,
        shippingAddress1: String?,
        shippingAddress2: String?,
        shippingCity: String?,
        shippingState: String?,
        shippingZip: String?,
        shippingCountry: String?
    ) {
        self.firstName = firstName
        self.lastName = lastName
        self.customerNumber = customerNumber
        self.email = email
        self.phone = phone
        self.customerId = customerId
        self.company = company
        self.billingAddress1 = billingAddress1
        self.billingAddress2 = billingAddress2
        self.billingCity = billingCity
        self.billingState = billingState
        self.billingZip = billingZip
        self.billingCountry = billingCountry
        self.billingPhone = billingPhone
        self.billingEmail = billingEmail
        self.shippingAddress1 = shippingAddress1
        self.shippingAddress2 = shippingAddress2
        self.shippingCity = shippingCity
        self.shippingState = shippingState
        self.shippingZip = shippingZip
        self.shippingCountry = shippingCountry
        super.init()
    }

    /// Bridge to the Swift value type used internally by the charge pipeline.
    ///
    /// - Returns: the customer data the charge pipeline carries.
    func toSwift() -> PayabliTTPCustomerData {
        PayabliTTPCustomerData(
            firstName: firstName,
            lastName: lastName,
            customerNumber: customerNumber,
            email: email,
            phone: phone,
            customerId: customerId.map { Int(truncating: $0) },
            company: company,
            billingAddress1: billingAddress1,
            billingAddress2: billingAddress2,
            billingCity: billingCity,
            billingState: billingState,
            billingZip: billingZip,
            billingCountry: billingCountry,
            billingPhone: billingPhone,
            billingEmail: billingEmail,
            shippingAddress1: shippingAddress1,
            shippingAddress2: shippingAddress2,
            shippingCity: shippingCity,
            shippingState: shippingState,
            shippingZip: shippingZip,
            shippingCountry: shippingCountry
        )
    }
}

/// ObjC companion for `TransactionResult`.
///
/// Returned to ObjC callers via the `charge(type:paymentDetails:customer:invoice:orderDescription:completion:)`
/// completion block when the underlying Swift `charge(...)` returns
/// successfully.
@objc(PayabliTTPTransactionResultObjC)
public final class PayabliTTPTransactionResultObjC: NSObject {
    @objc public let paymentTransId: String

    /// Bridge from the Swift value type returned by the charge pipeline.
    ///
    /// - Parameter result: the charge's result, as the Swift pipeline answered it.
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
    @objc public let currency: String?
    @objc public let paymentDescription: String?

    @objc public init(
        amount: NSDecimalNumber,
        serviceFee: NSDecimalNumber,
        currency: String?,
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

/// ObjC companion for `PayabliTTPInvoiceData`.
@objc(PayabliTTPInvoiceDataObjC)
public final class PayabliTTPInvoiceDataObjC: NSObject {
    @objc public let invoiceNumber: String?

    @objc public init(invoiceNumber: String?) {
        self.invoiceNumber = invoiceNumber
        super.init()
    }

    func toSwift() -> PayabliTTPInvoiceData {
        PayabliTTPInvoiceData(invoiceNumber: invoiceNumber)
    }
}

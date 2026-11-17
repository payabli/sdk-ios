import Foundation
import PayabliSDKCore

// MARK: - ObjC companions for transaction-data structs

// Objective-C companions to the value types in `PayabliTTPTransactionData.swift` and
// `PayabliTTPTypes.swift`. A public field changed on a Swift struct changes here in the same commit.

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

/// A card-present charge, for an Objective-C caller. Each property is a parameter of the Swift
/// `charge(paymentDetails:customer:invoice:orderDescription:attempt:)`, and one left unset takes that
/// parameter's default.
@objc(PayabliTTPChargeRequestObjC)
public final class PayabliTTPChargeRequestObjC: NSObject {
    @objc public let paymentDetails: PayabliTTPPaymentDetailsObjC
    @objc public var customer: PayabliTTPCustomerDataObjC?
    @objc public var invoice: PayabliTTPInvoiceDataObjC?
    @objc public var orderDescription: String?
    @objc public var attempt: PayabliAttempt = .newPayment

    /// - Parameter paymentDetails: the amount, service fee and currency to charge.
    @objc public init(paymentDetails: PayabliTTPPaymentDetailsObjC) {
        self.paymentDetails = paymentDetails
        super.init()
    }

    /// The attempt as the host set it. Objective-C passes an enum as a plain integer, so a number that names no case
    /// can arrive, and a switch over it traps.
    ///
    /// - Returns: the attempt.
    /// - Throws: a ``TapToPayError`` of type `.validation` naming `attempt`, for a number that names no case.
    func validatedAttempt() throws -> PayabliAttempt {
        guard let read = PayabliAttempt(rawValue: attempt.rawValue) else {
            throw objCValueRefusal(attempt.rawValue, of: PayabliAttempt.self, member: "attempt")
        }
        return read
    }
}

/// - Parameter value: the number the host passed.
/// - Parameter type: the enum it names no case of.
/// - Parameter member: the request member it fills.
/// - Returns: the refusal, naming that member.
private func objCValueRefusal(_ value: Int, of type: (some Any).Type, member: String) -> TapToPayError {
    TapToPayError(
        type: .validation,
        reason: PayabliErrorType.validation.message,
        detail: "\(member): \(value) is not a \(type) value."
    )
}

/// ObjC companion for `TransactionResult`.
///
/// Returned to ObjC callers via the `charge(_:completion:)` completion block when the underlying Swift
/// `charge(...)` returns successfully.
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
/// Swift `Decimal`. `currency` is always sent; an Objective-C caller passes
/// `PayabliCurrencyUsd`.
@objc(PayabliTTPPaymentDetailsObjC)
public final class PayabliTTPPaymentDetailsObjC: NSObject {
    @objc public let amount: NSDecimalNumber
    @objc public let serviceFee: NSDecimalNumber
    @objc public let currency: PayabliCurrency
    @objc public let paymentDescription: String?

    @objc public init(
        amount: NSDecimalNumber,
        serviceFee: NSDecimalNumber,
        currency: PayabliCurrency = .usd,
        paymentDescription: String?
    ) {
        self.amount = amount
        self.serviceFee = serviceFee
        self.currency = currency
        self.paymentDescription = paymentDescription
        super.init()
    }

    /// - Returns: the payment details.
    /// - Throws: a ``TapToPayError`` of type `.validation` naming `paymentDetails.currency`, when `currency` is a
    ///   number that names no case.
    func toSwift() throws -> PayabliTTPPaymentDetails {
        guard let read = PayabliCurrency(rawValue: currency.rawValue) else {
            throw objCValueRefusal(currency.rawValue, of: PayabliCurrency.self, member: "paymentDetails.currency")
        }
        return PayabliTTPPaymentDetails(
            amount: amount.decimalValue,
            serviceFee: serviceFee.decimalValue,
            currency: read,
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

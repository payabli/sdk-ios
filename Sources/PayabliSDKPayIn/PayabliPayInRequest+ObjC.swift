import Foundation
import PayabliSDKCore

/// A capture or an authorization, for an Objective-C caller. Each property is ``PayabliPayInRequestConfiguration``'s,
/// and a factory method per kind sets the payment method.
@objc(PayabliPayInRequestObjC)
public final class PayabliPayInRequestObjC: NSObject {
    let paymentMethod: PayabliPayInPaymentMethod

    @objc public var totalAmount: Double
    @objc public var serviceFee: NSNumber?
    @objc public var surchargeFee: NSNumber?
    @objc public var currency: String?
    @objc public var checkNumber: String?
    @objc public var checkUniqueId: String?
    @objc public var accountId: String?
    @objc public var customerData: PayabliPayInCustomerDataObjC?
    @objc public var ipAddress: String?
    @objc public var orderDescription: String?
    @objc public var orderId: String?
    @objc public var source: String?
    @objc public var subdomain: String?
    @objc public var subscriptionId: NSNumber?
    @objc public var paymentReference: String?
    @objc public var attempt: PayabliAttempt = .newPayment
    @objc public var achValidation: NSNumber?
    @objc public var forceCustomerCreation: NSNumber?
    @objc public var requiresLuhnCheck = PayabliPayInValidation.default.requiresLuhnCheck
    @objc public var validatesRoutingNumberChecksum = PayabliPayInValidation.default.validatesRoutingNumberChecksum

    private init(paymentMethod: PayabliPayInPaymentMethod, totalAmount: Double) {
        self.paymentMethod = paymentMethod
        self.totalAmount = totalAmount
        super.init()
    }

    /// - Parameter storedMethodId: the stored method to charge.
    /// - Parameter method: `card` or `bankAccount`.
    /// - Parameter totalAmount: the amount to charge.
    /// - Returns: the request, or nil when `method` names neither kind.
    @objc public static func stored(
        storedMethodId: String,
        method: String,
        totalAmount: Double
    ) -> PayabliPayInRequestObjC? {
        let type: PayabliPayInStoredMethodType
        switch method {
        case "card": type = .card
        case "bankAccount": type = .bankAccount
        default: return nil
        }
        let stored = PayabliPayInPaymentMethod.Stored(method: type, storedMethodId: storedMethodId)
        return PayabliPayInRequestObjC(paymentMethod: .stored(stored), totalAmount: totalAmount)
    }

    /// - Parameter cardNumber: the card number.
    /// - Parameter expiration: the expiry, as `MM/YY`.
    /// - Parameter cardholderName: the name on the card.
    /// - Parameter cvv: the card's security code.
    /// - Parameter billingZip: the billing postal code.
    /// - Parameter saveIfSuccess: whether to store the card when the payment succeeds.
    /// - Parameter totalAmount: the amount to charge.
    /// - Returns: the request.
    @objc public static func card(
        cardNumber: String,
        expiration: String,
        cardholderName: String,
        cvv: String,
        billingZip: String,
        saveIfSuccess: Bool,
        totalAmount: Double
    ) -> PayabliPayInRequestObjC {
        let data = PayabliPayInCardData(
            cardNumber: cardNumber,
            expiration: expiration,
            cardholderName: cardholderName,
            cvv: cvv,
            billingZip: billingZip
        )
        let card = PayabliPayInPaymentMethod.Card(data: data, saveIfSuccess: saveIfSuccess)
        return PayabliPayInRequestObjC(paymentMethod: .card(card), totalAmount: totalAmount)
    }

    /// - Parameter accountNumber: the account number.
    /// - Parameter accountType: `Checking` or `Savings`.
    /// - Parameter holderName: the account holder's name.
    /// - Parameter routingNumber: the routing number.
    /// - Parameter secCode: `PPD`, `WEB`, `TEL`, `CCD` or `BOC`; nil for `WEB`.
    /// - Parameter holderType: `personal` or `business`, or nil.
    /// - Parameter totalAmount: the amount to debit.
    /// - Returns: the request, or nil when a named value is none of those listed.
    @objc public static func bankAccount(
        accountNumber: String,
        accountType: String,
        holderName: String,
        routingNumber: String,
        secCode: String?,
        holderType: String?,
        totalAmount: Double
    ) -> PayabliPayInRequestObjC? {
        guard let type = PayabliPayInAccountType(rawValue: accountType) else { return nil }
        let code: PayabliPayInSecCode
        if let secCode {
            guard let named = PayabliPayInSecCode(rawValue: secCode) else { return nil }
            code = named
        } else {
            code = .web
        }
        var holder: PayabliPayInAccountHolderType?
        if let holderType {
            guard let named = PayabliPayInAccountHolderType(rawValue: holderType) else { return nil }
            holder = named
        }
        let data = PayabliPayInBankAccountData(
            accountNumber: accountNumber,
            accountType: type,
            holderName: holderName,
            routingNumber: routingNumber,
            secCode: code,
            holderType: holder
        )
        let account = PayabliPayInPaymentMethod.BankAccount(data: data)
        return PayabliPayInRequestObjC(paymentMethod: .bankAccount(account), totalAmount: totalAmount)
    }

    /// - Parameter device: the cloud device that reads the card.
    /// - Parameter saveIfSuccess: whether to store the card when the payment succeeds.
    /// - Parameter totalAmount: the amount to charge.
    /// - Returns: the request.
    @objc public static func cloudDevice(
        device: String,
        saveIfSuccess: Bool,
        totalAmount: Double
    ) -> PayabliPayInRequestObjC {
        let cloud = PayabliPayInPaymentMethod.CloudDevice(device: device, saveIfSuccess: saveIfSuccess)
        return PayabliPayInRequestObjC(paymentMethod: .cloudDevice(cloud), totalAmount: totalAmount)
    }

    /// - Parameter holderName: the name on the check.
    /// - Parameter totalAmount: the amount of the check.
    /// - Returns: the request.
    @objc public static func check(holderName: String, totalAmount: Double) -> PayabliPayInRequestObjC {
        let check = PayabliPayInPaymentMethod.Check(holderName: holderName)
        return PayabliPayInRequestObjC(paymentMethod: .check(check), totalAmount: totalAmount)
    }

    /// - Parameter totalAmount: the amount paid in cash.
    /// - Returns: the request.
    @objc public static func cash(totalAmount: Double) -> PayabliPayInRequestObjC {
        PayabliPayInRequestObjC(paymentMethod: .cash, totalAmount: totalAmount)
    }

    func toSwift() -> PayabliPayInRequest {
        let options = PayabliPayInRequestConfiguration(
            paymentDetails: PayabliPayInPaymentDetails(
                totalAmount: totalAmount,
                serviceFee: serviceFee?.doubleValue,
                surchargeFee: surchargeFee?.doubleValue,
                currency: currency,
                checkNumber: checkNumber,
                checkUniqueId: checkUniqueId
            ),
            accountId: accountId,
            customerData: customerData?.toSwift(),
            ipAddress: ipAddress,
            orderDescription: orderDescription,
            orderId: orderId,
            source: source,
            subdomain: subdomain,
            subscriptionId: subscriptionId?.int64Value,
            paymentReference: paymentReference,
            attempt: attempt,
            achValidation: achValidation?.boolValue,
            forceCustomerCreation: forceCustomerCreation?.boolValue,
            validation: PayabliPayInValidation(
                requiresLuhnCheck: requiresLuhnCheck,
                validatesRoutingNumberChecksum: validatesRoutingNumberChecksum
            )
        )
        return PayabliPayInRequest(paymentMethod: paymentMethod, options: options)
    }
}

/// A capture of an authorization, for an Objective-C caller. Each property is ``PayabliPayInAuthorizedRequest``'s.
@objc(PayabliPayInAuthorizedRequestObjC)
public final class PayabliPayInAuthorizedRequestObjC: NSObject {
    @objc public let transId: String
    @objc public var totalAmount: Double
    @objc public var serviceFee: NSNumber?
    @objc public var surchargeFee: NSNumber?
    @objc public var currency: String?

    /// - Parameter transId: the authorization to capture.
    /// - Parameter totalAmount: the amount to capture.
    @objc public init(transId: String, totalAmount: Double) {
        self.transId = transId
        self.totalAmount = totalAmount
        super.init()
    }

    func toSwift() -> PayabliPayInAuthorizedRequest {
        PayabliPayInAuthorizedRequest(
            transId: transId,
            paymentDetails: PayabliPayInPaymentDetails(
                totalAmount: totalAmount,
                serviceFee: serviceFee?.doubleValue,
                surchargeFee: surchargeFee?.doubleValue,
                currency: currency
            )
        )
    }
}

/// The payer, for an Objective-C caller. Each property is ``PayabliPayInCustomerData``'s.
@objc(PayabliPayInCustomerDataObjC)
public final class PayabliPayInCustomerDataObjC: NSObject {
    @objc public var additionalData: [String: String]?
    @objc public var billingAddress1: String?
    @objc public var billingAddress2: String?
    @objc public var billingCity: String?
    @objc public var billingCountry: String?
    @objc public var billingEmail: String?
    @objc public var billingPhone: String?
    @objc public var billingState: String?
    @objc public var billingZip: String?
    @objc public var company: String?
    @objc public var customerId: NSNumber?
    @objc public var customerNumber: String?
    @objc public var firstName: String?
    @objc public var identifierFields: [String]?
    @objc public var lastName: String?
    @objc public var shippingAddress1: String?
    @objc public var shippingAddress2: String?
    @objc public var shippingCity: String?
    @objc public var shippingCountry: String?
    @objc public var shippingState: String?
    @objc public var shippingZip: String?

    @objc override public init() {
        super.init()
    }

    func toSwift() -> PayabliPayInCustomerData {
        var customer = PayabliPayInCustomerData()
        customer.additionalData = additionalData
        customer.billingAddress1 = billingAddress1
        customer.billingAddress2 = billingAddress2
        customer.billingCity = billingCity
        customer.billingCountry = billingCountry
        customer.billingEmail = billingEmail
        customer.billingPhone = billingPhone
        customer.billingState = billingState
        customer.billingZip = billingZip
        customer.company = company
        customer.customerId = customerId?.int64Value
        customer.customerNumber = customerNumber
        customer.firstName = firstName
        customer.identifierFields = identifierFields
        customer.lastName = lastName
        customer.shippingAddress1 = shippingAddress1
        customer.shippingAddress2 = shippingAddress2
        customer.shippingCity = shippingCity
        customer.shippingCountry = shippingCountry
        customer.shippingState = shippingState
        customer.shippingZip = shippingZip
        return customer
    }
}

/// What a payment call returned, for an Objective-C caller. Each field is ``PayabliPayInResult``'s.
@objc(PayabliPayInResultObjC)
public final class PayabliPayInResultObjC: NSObject {
    @objc public let code: String
    @objc public let reason: String?
    @objc public let explanation: String?
    @objc public let action: String?
    @objc public let transaction: PayabliPayInTransactionObjC?

    init(_ result: PayabliPayInResult) {
        code = result.code
        reason = result.reason
        explanation = result.explanation
        action = result.action
        transaction = result.transaction.map(PayabliPayInTransactionObjC.init)
        super.init()
    }
}

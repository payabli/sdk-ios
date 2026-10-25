import Foundation

/// The request family's descriptions print kinds and flags, never a payer's values.
///
/// A request meets `String(describing:)` in assertion failures and diagnostic output, so the
/// card prints its kind, not its number, and the two requests compose these.
extension PayabliPayInCardData: CustomStringConvertible {
    /// No field of a card belongs in a message, the expiry included.
    public var description: String {
        "PayabliPayInCardData"
    }
}

extension PayabliPayInBankAccountData: CustomStringConvertible {
    /// The account type names checking or savings, which is how the account is debited rather than
    /// anything the payer entered.
    public var description: String {
        "PayabliPayInBankAccountData(accountType: \(accountType))"
    }
}

extension PayabliPayInMethodInput: CustomStringConvertible {
    /// The kind of instrument entered, without its details.
    public var description: String {
        switch self {
        case .card: "PayabliPayInMethodInput.card"
        case .bankAccount: "PayabliPayInMethodInput.bankAccount"
        }
    }
}

extension PayabliPayInPaymentDetails: CustomStringConvertible {
    /// An amount is not a secret, and it is also not something a log needs.
    public var description: String {
        "PayabliPayInPaymentDetails(hasServiceFee: \(serviceFee != nil))"
    }
}

extension PayabliPayInCustomerData: CustomStringConvertible {
    /// Every field here is personal data, so none is rendered; the flag is a question about the
    /// paypoint's configuration, not the payer.
    public var description: String {
        "PayabliPayInCustomerData(hasAdditionalData: \(additionalData != nil))"
    }
}

extension PayabliPayInVendorData: CustomStringConvertible {
    /// A vendor's identifiers name the merchant's own record, and stay out with the payer's.
    public var description: String {
        "PayabliPayInVendorData"
    }
}

extension PayabliPayInTokenStorageOptions: CustomStringConvertible {
    /// The store's settings print nothing, because the customer data they may carry is the payer's.
    public var description: String {
        "PayabliPayInTokenStorageOptions"
    }
}

extension PayabliPayInRequestConfiguration: CustomStringConvertible {
    /// The transaction's settings print nothing, for the same reason as the store's.
    public var description: String {
        "PayabliPayInRequestConfiguration"
    }
}

extension PayabliPayInPaymentMethod: CustomStringConvertible {
    /// The method's kind; a stored method's identifier and a check's payer are values it holds.
    public var description: String {
        switch self {
        case .card: "PayabliPayInPaymentMethod.card"
        case .bankAccount: "PayabliPayInPaymentMethod.bankAccount"
        case .stored: "PayabliPayInPaymentMethod.stored"
        case .cloudDevice: "PayabliPayInPaymentMethod.cloudDevice"
        case .check: "PayabliPayInPaymentMethod.check"
        case .cash: "PayabliPayInPaymentMethod.cash"
        }
    }
}

extension PayabliPayInPaymentMethod.Card: CustomStringConvertible {
    public var description: String {
        "PayabliPayInPaymentMethod.Card"
    }
}

extension PayabliPayInPaymentMethod.BankAccount: CustomStringConvertible {
    public var description: String {
        "PayabliPayInPaymentMethod.BankAccount"
    }
}

extension PayabliPayInPaymentMethod.Stored: CustomStringConvertible {
    public var description: String {
        "PayabliPayInPaymentMethod.Stored"
    }
}

extension PayabliPayInPaymentMethod.CloudDevice: CustomStringConvertible {
    public var description: String {
        "PayabliPayInPaymentMethod.CloudDevice"
    }
}

extension PayabliPayInPaymentMethod.Check: CustomStringConvertible {
    public var description: String {
        "PayabliPayInPaymentMethod.Check"
    }
}

extension PayabliPayInStoreRequest: CustomStringConvertible {
    /// The store request, carrying its instrument's kind and nothing else.
    public var description: String {
        "PayabliPayInStoreRequest(instrument: \(instrument), options: \(options))"
    }
}

extension PayabliPayInRequest: CustomStringConvertible {
    /// The charge request, carrying its method's kind and nothing else.
    public var description: String {
        "PayabliPayInRequest(paymentMethod: \(paymentMethod), options: \(options))"
    }
}

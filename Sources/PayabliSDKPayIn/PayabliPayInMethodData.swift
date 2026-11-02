public struct PayabliPayInCardData: CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    let cardNumber: SensitiveDigits
    public var expiry: String
    public var holderName: String
    let securityCode: SensitiveDigits
    public var postalCode: String

    /// Card data for a payment or a stored method. The card number and the security code are copied into
    /// buffers the SDK overwrites, and can't be read back from the value.
    ///
    /// - Parameter cardNumber: the card number.
    /// - Parameter expiry: the expiry, as `MM/YY` or `MMYY`.
    /// - Parameter holderName: the cardholder's name.
    /// - Parameter securityCode: the security code.
    /// - Parameter postalCode: the billing postal code.
    public init(
        cardNumber: String,
        expiry: String,
        holderName: String,
        securityCode: String,
        postalCode: String
    ) {
        self.init(
            cardNumber: SensitiveDigits.ofString(cardNumber),
            expiry: expiry,
            holderName: holderName,
            securityCode: SensitiveDigits.ofString(securityCode),
            postalCode: postalCode
        )
    }

    init(
        cardNumber: SensitiveDigits,
        expiry: String,
        holderName: String,
        securityCode: SensitiveDigits,
        postalCode: String
    ) {
        self.cardNumber = cardNumber
        self.expiry = expiry
        self.holderName = holderName
        self.securityCode = securityCode
        self.postalCode = postalCode
    }

    /// Nothing about the card: an interpolated value reaches a crash report, which does not redact.
    public var description: String {
        "PayabliPayInCardData"
    }

    /// The same redacted text on the debug route, which `String(reflecting:)` and a debugger's `po`
    /// render. `dump()` and the variables view render the stored fields, which no protocol redacts.
    public var debugDescription: String {
        description
    }
}

public struct PayabliPayInBankAccountData: CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    let accountNumber: SensitiveDigits
    public var accountType: PayabliPayInAccountType
    public var holderName: String
    public var routingNumber: String
    public var secCode: PayabliPayInSecCode?
    public var holderType: PayabliPayInAccountHolderType?
    public var device: String?

    /// Bank account data for a payment or a stored method. The account number is copied into a buffer
    /// the SDK overwrites, and can't be read back from the value.
    ///
    /// - Parameter accountNumber: the account number.
    /// - Parameter accountType: checking or savings.
    /// - Parameter holderName: the account holder's name.
    /// - Parameter routingNumber: the routing number.
    /// - Parameter secCode: the ACH entry class; `.web` unless set.
    /// - Parameter holderType: personal or business, when known.
    /// - Parameter device: the device identifier, when one is sent.
    public init(
        accountNumber: String,
        accountType: PayabliPayInAccountType,
        holderName: String,
        routingNumber: String,
        secCode: PayabliPayInSecCode? = .web,
        holderType: PayabliPayInAccountHolderType? = nil,
        device: String? = nil
    ) {
        self.init(
            accountNumber: SensitiveDigits.ofString(accountNumber),
            accountType: accountType,
            holderName: holderName,
            routingNumber: routingNumber,
            secCode: secCode,
            holderType: holderType,
            device: device
        )
    }

    init(
        accountNumber: SensitiveDigits,
        accountType: PayabliPayInAccountType,
        holderName: String,
        routingNumber: String,
        secCode: PayabliPayInSecCode? = .web,
        holderType: PayabliPayInAccountHolderType? = nil,
        device: String? = nil
    ) {
        self.accountNumber = accountNumber
        self.accountType = accountType
        self.holderName = holderName
        self.routingNumber = routingNumber
        self.secCode = secCode
        self.holderType = holderType
        self.device = device
    }

    /// The account's kind alone: an interpolated value reaches a crash report, which does not redact,
    /// and the number and the holder are what this type exists to keep out of a message.
    public var description: String {
        "PayabliPayInBankAccountData(accountType=\(accountType.rawValue))"
    }

    /// The same redacted text on the debug route, which `String(reflecting:)` and a debugger's `po`
    /// render. `dump()` and the variables view render the stored fields, which no protocol redacts.
    public var debugDescription: String {
        description
    }
}

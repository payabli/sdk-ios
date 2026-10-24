public struct PayabliPayInCardData: CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    public var cardNumber: SensitiveDigits
    public var expiry: String
    public var holderName: String
    public var securityCode: SensitiveDigits
    public var postalCode: String

    public init(
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

    /// Nothing about the card: an interpolated value reaches a crash report and a debugger, neither of
    /// which redacts.
    public var description: String {
        "PayabliPayInCardData"
    }

    /// The same redacted text on the debug route, which is what a debugger and `String(reflecting:)`
    /// render.
    public var debugDescription: String {
        description
    }
}

public struct PayabliPayInBankAccountData: CustomStringConvertible, CustomDebugStringConvertible, Sendable {
    public var accountNumber: SensitiveDigits
    public var accountType: PayabliPayInAccountType
    public var holderName: String
    public var routingNumber: String
    public var secCode: PayabliPayInSecCode?
    public var holderType: PayabliPayInAccountHolderType?
    public var device: String?

    public init(
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

    /// The account's kind alone: an interpolated value reaches a crash report and a debugger, neither
    /// of which redacts, and the number and the holder are what this type exists to keep out of a
    /// message.
    public var description: String {
        "PayabliPayInBankAccountData(accountType=\(accountType.rawValue))"
    }

    /// The same redacted text on the debug route, which is what a debugger and `String(reflecting:)`
    /// render.
    public var debugDescription: String {
        description
    }
}

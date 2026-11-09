public struct PayabliPayInCardData: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable,
    Sendable
{
    let cardNumber: SensitiveDigits
    public var expiryMonth: Int
    public var expiryYear: Int
    let securityCode: SensitiveDigits
    public var holderName: String
    public var postalCode: String

    /// Card data for a payment or a stored method. The card number and the security code are copied into
    /// buffers the SDK overwrites, and can't be read back from the value.
    ///
    /// The expiry is checked when the card is sent, not here: a month outside 1 to 12, a year that isn't four
    /// digits or is after 2099, or a month before the current one is refused before anything is sent.
    ///
    /// - Parameter cardNumber: the card number.
    /// - Parameter expiryMonth: the expiry month, 1 to 12.
    /// - Parameter expiryYear: the expiry year, four digits.
    /// - Parameter securityCode: the security code.
    /// - Parameter holderName: the cardholder's name.
    /// - Parameter postalCode: the billing postal code.
    public init(
        cardNumber: String,
        expiryMonth: Int,
        expiryYear: Int,
        securityCode: String,
        holderName: String,
        postalCode: String
    ) {
        self.init(
            cardNumber: SensitiveDigits.ofString(cardNumber),
            expiryMonth: expiryMonth,
            expiryYear: expiryYear,
            securityCode: SensitiveDigits.ofString(securityCode),
            holderName: holderName,
            postalCode: postalCode
        )
    }

    init(
        cardNumber: SensitiveDigits,
        expiryMonth: Int,
        expiryYear: Int,
        securityCode: SensitiveDigits,
        holderName: String,
        postalCode: String
    ) {
        self.cardNumber = cardNumber
        self.expiryMonth = expiryMonth
        self.expiryYear = expiryYear
        self.securityCode = securityCode
        self.holderName = holderName
        self.postalCode = postalCode
    }

    /// Nothing about the card: an interpolated value reaches a crash report, which does not redact.
    public var description: String {
        "PayabliPayInCardData"
    }

    /// The same redacted text on the debug route, which `String(reflecting:)` and a debugger's `po`
    /// render. A debugger's variables view reads memory directly, which no protocol redacts.
    public var debugDescription: String {
        description
    }

    /// No fields, so `dump()` and a `Mirror` walk show the type name alone, as `description` does.
    public var customMirror: Mirror {
        Mirror(self, children: [], displayStyle: .struct)
    }
}

public struct PayabliPayInBankAccountData: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable,
    Sendable
{
    let accountNumber: SensitiveDigits
    public var routingNumber: String
    public var accountType: PayabliPayInAccountType
    public var holderName: String
    public var holderType: PayabliPayInAccountHolderType?
    public var secCode: PayabliPayInSecCode?

    /// Bank account data for a payment or a stored method. The account number is copied into a buffer
    /// the SDK overwrites, and can't be read back from the value.
    ///
    /// - Parameter accountNumber: the account number.
    /// - Parameter routingNumber: the routing number.
    /// - Parameter accountType: checking or savings.
    /// - Parameter holderName: the account holder's name.
    /// - Parameter holderType: personal or business, when known.
    /// - Parameter secCode: the ACH entry class; `WEB` is sent when none is given.
    public init(
        accountNumber: String,
        routingNumber: String,
        accountType: PayabliPayInAccountType,
        holderName: String,
        holderType: PayabliPayInAccountHolderType? = nil,
        secCode: PayabliPayInSecCode? = nil
    ) {
        self.init(
            accountNumber: SensitiveDigits.ofString(accountNumber),
            routingNumber: routingNumber,
            accountType: accountType,
            holderName: holderName,
            holderType: holderType,
            secCode: secCode
        )
    }

    init(
        accountNumber: SensitiveDigits,
        routingNumber: String,
        accountType: PayabliPayInAccountType,
        holderName: String,
        holderType: PayabliPayInAccountHolderType? = nil,
        secCode: PayabliPayInSecCode? = nil
    ) {
        self.accountNumber = accountNumber
        self.routingNumber = routingNumber
        self.accountType = accountType
        self.holderName = holderName
        self.holderType = holderType
        self.secCode = secCode
    }

    /// The account's kind alone: an interpolated value reaches a crash report, which does not redact,
    /// and the number and the holder are what this type exists to keep out of a message.
    public var description: String {
        "PayabliPayInBankAccountData(accountType=\(accountType.rawValue))"
    }

    /// The same redacted text on the debug route, which `String(reflecting:)` and a debugger's `po`
    /// render. A debugger's variables view reads memory directly, which no protocol redacts.
    public var debugDescription: String {
        description
    }

    /// The account type alone, so `dump()` and a `Mirror` walk show what `description` does.
    public var customMirror: Mirror {
        Mirror(self, children: ["accountType": accountType], displayStyle: .struct)
    }
}

import Foundation

/// The customer block in a tokenization or payment request.
/// See PRD §8 "Card Payload".
public struct CustomerDataBlock: Encodable, Sendable {
    public let customerId: Int

    public init(customerId: Int) {
        self.customerId = customerId
    }
}

/// Card tokenization payload (PRD §8 "Card Payload").
public struct CardTokenizationPayload: Encodable, Sendable {
    public let method: String
    public let cardnumber: String
    public let cardexp: String // "MMYY"
    public let cardcvv: String
    public let cardHolder: String
    public let cardzip: String

    public init(
        cardnumber: String,
        cardexp: String,
        cardcvv: String,
        cardHolder: String,
        cardzip: String
    ) {
        self.method = "card"
        self.cardnumber = cardnumber
        self.cardexp = cardexp
        self.cardcvv = cardcvv
        self.cardHolder = cardHolder
        self.cardzip = cardzip
    }
}

/// Account type for ACH tokenization.
public enum ACHAccountType: String, Sendable, Codable {
    case checking = "Checking"
    case savings = "Savings"
}

/// Holder type for ACH tokenization.
public enum ACHHolderType: String, Sendable, Codable {
    case personal = "personal"
    case business = "business"
}

/// ACH tokenization payload (PRD §8 "ACH Payload").
public struct ACHTokenizationPayload: Encodable, Sendable {
    public let method: String
    public let achAccount: String
    public let achRouting: String
    public let achAccountType: ACHAccountType
    public let achHolder: String
    public let achHolderType: ACHHolderType
    public let achCode: String

    public init(
        achAccount: String,
        achRouting: String,
        achAccountType: ACHAccountType,
        achHolder: String,
        achHolderType: ACHHolderType
    ) {
        self.method = "ach"
        self.achAccount = achAccount
        self.achRouting = achRouting
        self.achAccountType = achAccountType
        self.achHolder = achHolder
        self.achHolderType = achHolderType
        self.achCode = "WEB" // PRD FR-2.6
    }
}

/// Top-level tokenization request (card variant).
public struct CardTokenizationRequest: Encodable, Sendable {
    public let customerData: CustomerDataBlock
    public let entryPoint: String
    public let fallbackAuth: Bool
    public let paymentMethod: CardTokenizationPayload

    public init(
        customerData: CustomerDataBlock,
        entryPoint: String,
        paymentMethod: CardTokenizationPayload,
        fallbackAuth: Bool = true
    ) {
        self.customerData = customerData
        self.entryPoint = entryPoint
        self.fallbackAuth = fallbackAuth
        self.paymentMethod = paymentMethod
    }
}

/// Top-level tokenization request (ACH variant).
public struct ACHTokenizationRequest: Encodable, Sendable {
    public let customerData: CustomerDataBlock
    public let entryPoint: String
    public let paymentMethod: ACHTokenizationPayload

    public init(
        customerData: CustomerDataBlock,
        entryPoint: String,
        paymentMethod: ACHTokenizationPayload
    ) {
        self.customerData = customerData
        self.entryPoint = entryPoint
        self.paymentMethod = paymentMethod
    }
}

/// Apple Pay tokenization payload (PRD §8 "Apple Pay Payload").
public struct ApplePayTokenizationPayload: Encodable, Sendable {
    public let method: String
    public let applePayToken: String
    public let applePayNetwork: String?
    public let applePayDisplayName: String?

    public init(
        applePayToken: String,
        applePayNetwork: String?,
        applePayDisplayName: String?
    ) {
        self.method = "applepay"
        self.applePayToken = applePayToken
        self.applePayNetwork = applePayNetwork
        self.applePayDisplayName = applePayDisplayName
    }
}

/// Top-level tokenization request (Apple Pay variant).
public struct ApplePayTokenizationRequest: Encodable, Sendable {
    public let customerData: CustomerDataBlock
    public let entryPoint: String
    public let paymentMethod: ApplePayTokenizationPayload

    public init(
        customerData: CustomerDataBlock,
        entryPoint: String,
        paymentMethod: ApplePayTokenizationPayload
    ) {
        self.customerData = customerData
        self.entryPoint = entryPoint
        self.paymentMethod = paymentMethod
    }
}

/// Tokenization response body returned by `POST /api/TokenStorage/add`.
///
/// The API returns a token string. Different deployments may wrap it in an
/// envelope; we model the common shape and fall back to plain-string parsing.
public struct TokenizationResponse: Decodable, Sendable {
    public let token: String?
    public let responseData: String?
    public let isSuccess: Bool?

    public var resolvedToken: String? {
        responseData ?? token
    }
}

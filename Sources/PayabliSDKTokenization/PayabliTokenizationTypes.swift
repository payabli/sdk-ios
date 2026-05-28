import Foundation
import PayabliSDKCore

public enum PayabliTokenizationMethod: String, CaseIterable, Identifiable, Sendable {
    case card
    case ach

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .card: return "Card"
        case .ach: return "ACH"
        }
    }
}

public enum PayabliTokenizationCardBrand: String, CaseIterable, Identifiable, Sendable, Equatable {
    case unknown
    case visa
    case mastercard
    case americanExpress
    case discover
    case dinersClub
    case jcb
    case unionPay

    public var id: String {
        rawValue
    }

    public var displayName: String {
        switch self {
        case .unknown: return "Card"
        case .visa: return "Visa"
        case .mastercard: return "Mastercard"
        case .americanExpress: return "American Express"
        case .discover: return "Discover"
        case .dinersClub: return "Diners Club"
        case .jcb: return "JCB"
        case .unionPay: return "UnionPay"
        }
    }

    var brandAssetName: String? {
        switch self {
        case .visa:
            return "brand-visa"
        case .mastercard:
            return "brand-mastercard"
        case .americanExpress:
            return "brand-amex"
        case .discover:
            return "brand-discover"
        case .unknown, .dinersClub, .jcb, .unionPay:
            return nil
        }
    }

    public static func detect(cardNumber: String) -> PayabliTokenizationCardBrand {
        let digits = cardNumber.digitsOnly
        guard !digits.isEmpty else { return .unknown }

        if digits.hasPrefix("4") {
            return .visa
        }
        if prefixValue(digits, length: 2).map({ (51 ... 55).contains($0) }) == true ||
            prefixValue(digits, length: 4).map({ (2221 ... 2720).contains($0) }) == true {
            return .mastercard
        }
        if ["34", "37"].contains(where: digits.hasPrefix) {
            return .americanExpress
        }
        if digits.hasPrefix("6011") ||
            digits.hasPrefix("65") ||
            prefixValue(digits, length: 3).map({ (644 ... 649).contains($0) }) == true ||
            prefixValue(digits, length: 6).map({ (622_126 ... 622_925).contains($0) }) == true {
            return .discover
        }
        if prefixValue(digits, length: 3).map({ (300 ... 305).contains($0) }) == true ||
            ["36", "38", "39"].contains(where: digits.hasPrefix) {
            return .dinersClub
        }
        if prefixValue(digits, length: 4).map({ (3528 ... 3589).contains($0) }) == true {
            return .jcb
        }
        if digits.hasPrefix("62") {
            return .unionPay
        }
        return .unknown
    }

    private static func prefixValue(_ digits: String, length: Int) -> Int? {
        guard digits.count >= length else { return nil }
        return Int(digits.prefix(length))
    }
}

public enum PayabliACHAccountType: String, CaseIterable, Identifiable, Codable, Sendable {
    case checking = "Checking"
    case savings = "Savings"

    public var id: String {
        rawValue
    }
}

public enum PayabliACHHolderType: String, CaseIterable, Identifiable, Codable, Sendable {
    case personal
    case business

    public var id: String {
        rawValue
    }
}

public enum PayabliACHSecCode: String, CaseIterable, Identifiable, Codable, Sendable {
    case ppd = "PPD"
    case web = "WEB"
    case tel = "TEL"
    case ccd = "CCD"
    case boc = "BOC"

    public var id: String {
        rawValue
    }
}

public struct PayabliTokenizationValidation: Sendable {
    public var requiresLuhnCheck: Bool
    public var validatesACHRoutingChecksum: Bool

    public init(
        requiresLuhnCheck: Bool = true,
        validatesACHRoutingChecksum: Bool = true
    ) {
        self.requiresLuhnCheck = requiresLuhnCheck
        self.validatesACHRoutingChecksum = validatesACHRoutingChecksum
    }

    public static let `default` = PayabliTokenizationValidation()
}

public enum PayabliTokenizationError: PayabliError {
    case invalidInput(String)
    case missingAccessToken
    case tokenizationFailed(PayabliTokenizationFailure)

    public var code: PayabliErrorCode {
        switch self {
        case .invalidInput:
            return .validation
        case .missingAccessToken:
            return .missingToken
        case .tokenizationFailed:
            return .unknown
        }
    }

    public var reason: String {
        switch self {
        case let .invalidInput(message):
            return message
        case .missingAccessToken:
            return "Missing access token"
        case let .tokenizationFailed(failure):
            return failure.reason
        }
    }

    public var detail: String? {
        switch self {
        case .invalidInput, .missingAccessToken:
            return nil
        case let .tokenizationFailed(failure):
            return failure.detail
        }
    }
}

public struct PayabliTokenizationFailure: Codable, Sendable, Equatable {
    public let isSuccess: Bool?
    public let responseText: String
    public let responseCode: Int?
    public let resultCode: Int?
    public let resultText: String?
    public let explanation: String?
    public let todoAction: String?
    public let httpStatusCode: Int?

    public init(
        isSuccess: Bool? = nil,
        responseText: String,
        responseCode: Int? = nil,
        resultCode: Int? = nil,
        resultText: String? = nil,
        explanation: String? = nil,
        todoAction: String? = nil,
        httpStatusCode: Int? = nil
    ) {
        self.isSuccess = isSuccess
        self.responseText = responseText
        self.responseCode = responseCode
        self.resultCode = resultCode
        self.resultText = resultText
        self.explanation = explanation
        self.todoAction = todoAction
        self.httpStatusCode = httpStatusCode
    }

    public var reason: String {
        if let explanation = explanation?.trimmed.nilIfEmpty {
            return explanation
        }
        if let resultText = resultText?.trimmed.nilIfEmpty {
            return resultText
        }
        if let httpStatusCode, httpStatusCode >= 500 {
            return "Unable to tokenize right now. Please try again."
        }
        return responseText.trimmed.nilIfEmpty ?? "Tokenization failed."
    }

    public var detail: String? {
        todoAction?.trimmed.nilIfEmpty
    }
}

public struct PayabliCardTokenizationData: Sendable {
    public var cardNumber: String
    public var expiration: String
    public var cardholderName: String
    public var cvv: String?
    public var billingZip: String

    public init(
        cardNumber: String,
        expiration: String,
        cardholderName: String,
        cvv: String? = nil,
        billingZip: String
    ) {
        self.cardNumber = cardNumber
        self.expiration = expiration
        self.cardholderName = cardholderName
        self.cvv = cvv
        self.billingZip = billingZip
    }
}

public struct PayabliACHTokenizationData: Sendable {
    public var accountNumber: String
    public var accountType: PayabliACHAccountType
    public var holderName: String
    public var routingNumber: String
    public var secCode: PayabliACHSecCode?
    public var holderType: PayabliACHHolderType?
    public var device: String?

    public init(
        accountNumber: String,
        accountType: PayabliACHAccountType,
        holderName: String,
        routingNumber: String,
        secCode: PayabliACHSecCode? = .web,
        holderType: PayabliACHHolderType? = nil,
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
}

public enum PayabliTokenizationPaymentMethod: Sendable {
    case card(PayabliCardTokenizationData)
    case ach(PayabliACHTokenizationData)

    public var method: PayabliTokenizationMethod {
        switch self {
        case .card: return .card
        case .ach: return .ach
        }
    }
}

public struct PayabliTokenizationCustomerData: Codable, Sendable {
    public var additionalData: [String: String]?
    public var billingAddress1: String?
    public var billingAddress2: String?
    public var billingCity: String?
    public var billingCountry: String?
    public var billingEmail: String?
    public var billingPhone: String?
    public var billingState: String?
    public var billingZip: String?
    public var company: String?
    public var customerId: Int64?
    public var customerNumber: String?
    public var firstName: String?
    public var identifierFields: [String]?
    public var lastName: String?
    public var shippingAddress1: String?
    public var shippingAddress2: String?
    public var shippingCity: String?
    public var shippingCountry: String?
    public var shippingState: String?
    public var shippingZip: String?

    public init(
        additionalData: [String: String]? = nil,
        billingAddress1: String? = nil,
        billingAddress2: String? = nil,
        billingCity: String? = nil,
        billingCountry: String? = nil,
        billingEmail: String? = nil,
        billingPhone: String? = nil,
        billingState: String? = nil,
        billingZip: String? = nil,
        company: String? = nil,
        customerId: Int64? = nil,
        customerNumber: String? = nil,
        firstName: String? = nil,
        identifierFields: [String]? = nil,
        lastName: String? = nil,
        shippingAddress1: String? = nil,
        shippingAddress2: String? = nil,
        shippingCity: String? = nil,
        shippingCountry: String? = nil,
        shippingState: String? = nil,
        shippingZip: String? = nil
    ) {
        self.additionalData = additionalData
        self.billingAddress1 = billingAddress1
        self.billingAddress2 = billingAddress2
        self.billingCity = billingCity
        self.billingCountry = billingCountry
        self.billingEmail = billingEmail
        self.billingPhone = billingPhone
        self.billingState = billingState
        self.billingZip = billingZip
        self.company = company
        self.customerId = customerId
        self.customerNumber = customerNumber
        self.firstName = firstName
        self.identifierFields = identifierFields
        self.lastName = lastName
        self.shippingAddress1 = shippingAddress1
        self.shippingAddress2 = shippingAddress2
        self.shippingCity = shippingCity
        self.shippingCountry = shippingCountry
        self.shippingState = shippingState
        self.shippingZip = shippingZip
    }
}

public struct PayabliTokenizationVendorData: Codable, Sendable {
    public var vendorId: Int64?
    public var vendorNumber: String?

    public init(vendorId: Int64? = nil, vendorNumber: String? = nil) {
        self.vendorId = vendorId
        self.vendorNumber = vendorNumber
    }
}

public struct PayabliTokenizationOptions: Sendable {
    public var achValidation: Bool?
    public var createAnonymous: Bool?
    public var forceCustomerCreation: Bool?
    public var temporary: Bool?
    public var idempotencyKey: String?
    public var customerData: PayabliTokenizationCustomerData?
    public var vendorData: PayabliTokenizationVendorData?
    public var fallbackAuth: Bool?
    public var fallbackAuthAmount: Int?
    public var methodDescription: String?
    public var source: String?
    public var subdomain: String?
    public var validation: PayabliTokenizationValidation

    public init(
        achValidation: Bool? = nil,
        createAnonymous: Bool? = nil,
        forceCustomerCreation: Bool? = nil,
        temporary: Bool? = nil,
        idempotencyKey: String? = nil,
        customerData: PayabliTokenizationCustomerData? = nil,
        vendorData: PayabliTokenizationVendorData? = nil,
        fallbackAuth: Bool? = nil,
        fallbackAuthAmount: Int? = nil,
        methodDescription: String? = nil,
        source: String? = nil,
        subdomain: String? = nil,
        validation: PayabliTokenizationValidation = .default
    ) {
        self.achValidation = achValidation
        self.createAnonymous = createAnonymous
        self.forceCustomerCreation = forceCustomerCreation
        self.temporary = temporary
        self.idempotencyKey = idempotencyKey
        self.customerData = customerData
        self.vendorData = vendorData
        self.fallbackAuth = fallbackAuth
        self.fallbackAuthAmount = fallbackAuthAmount
        self.methodDescription = methodDescription
        self.source = source
        self.subdomain = subdomain
        self.validation = validation
    }
}

public struct PayabliTokenizationAPIResponseData: Codable, Sendable, Equatable {
    public let referenceId: String?
    public let resultCode: Int?
    public let resultText: String?
    public let explanation: String?
    public let todoAction: String?
    public let customerId: Int64?
    public let methodReferenceId: String?

    public init(
        referenceId: String? = nil,
        resultCode: Int? = nil,
        resultText: String? = nil,
        explanation: String? = nil,
        todoAction: String? = nil,
        customerId: Int64? = nil,
        methodReferenceId: String? = nil
    ) {
        self.referenceId = referenceId
        self.resultCode = resultCode
        self.resultText = resultText
        self.explanation = explanation
        self.todoAction = todoAction
        self.customerId = customerId
        self.methodReferenceId = methodReferenceId
    }

    enum CodingKeys: String, CodingKey {
        case referenceId
        case resultCode
        case resultText
        case explanation
        case todoAction
        case customerId
        case methodReferenceId
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        referenceId = try c.decodeIfPresent(String.self, forKey: .referenceId)
        resultCode = c.decodeLossyIntIfPresent(forKey: .resultCode)
        resultText = try c.decodeIfPresent(String.self, forKey: .resultText)
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation)
        todoAction = try c.decodeIfPresent(String.self, forKey: .todoAction)
        customerId = c.decodeLossyInt64IfPresent(forKey: .customerId)
        methodReferenceId = try c.decodeIfPresent(String.self, forKey: .methodReferenceId)
    }
}

public struct PayabliTokenizationAPIResponse: Codable, Sendable, Equatable {
    public let isSuccess: Bool?
    public let responseText: String
    public let responseCode: Int?
    public let responseData: PayabliTokenizationAPIResponseData?

    public init(
        isSuccess: Bool? = nil,
        responseText: String,
        responseCode: Int? = nil,
        responseData: PayabliTokenizationAPIResponseData? = nil
    ) {
        self.isSuccess = isSuccess
        self.responseText = responseText
        self.responseCode = responseCode
        self.responseData = responseData
    }

    enum CodingKeys: String, CodingKey {
        case isSuccess
        case responseText
        case responseCode
        case responseData
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isSuccess = try c.decodeIfPresent(Bool.self, forKey: .isSuccess)
        responseText = try c.decode(String.self, forKey: .responseText)
        responseCode = c.decodeLossyIntIfPresent(forKey: .responseCode)
        responseData = try? c.decodeIfPresent(PayabliTokenizationAPIResponseData.self, forKey: .responseData)
    }

    public func failure(httpStatusCode: Int? = nil) -> PayabliTokenizationFailure {
        PayabliTokenizationFailure(
            isSuccess: isSuccess,
            responseText: responseText,
            responseCode: responseCode,
            resultCode: responseData?.resultCode,
            resultText: responseData?.resultText,
            explanation: responseData?.explanation,
            todoAction: responseData?.todoAction,
            httpStatusCode: httpStatusCode
        )
    }
}

public struct PayabliTokenizedMethod: Sendable, Equatable {
    public let storedMethodId: String?
    public let methodReferenceId: String?
    public let resultCode: Int?
    public let resultText: String?
    public let customerId: Int64?
    public let responseText: String
    public let apiResponse: PayabliTokenizationAPIResponse

    public init(
        storedMethodId: String?,
        methodReferenceId: String?,
        resultCode: Int?,
        resultText: String?,
        customerId: Int64?,
        responseText: String,
        apiResponse: PayabliTokenizationAPIResponse? = nil
    ) {
        self.storedMethodId = storedMethodId
        self.methodReferenceId = methodReferenceId
        self.resultCode = resultCode
        self.resultText = resultText
        self.customerId = customerId
        self.responseText = responseText
        self.apiResponse = apiResponse ?? PayabliTokenizationAPIResponse(
            responseText: responseText,
            responseData: PayabliTokenizationAPIResponseData(
                referenceId: storedMethodId,
                resultCode: resultCode,
                resultText: resultText,
                customerId: customerId,
                methodReferenceId: methodReferenceId
            )
        )
    }
}

extension PayabliTokenizationPaymentMethod: Encodable {
    enum CodingKeys: String, CodingKey {
        case method
        case cardcvv
        case cardexp
        case cardHolder
        case cardnumber
        case cardzip
        case achAccount
        case achAccountType
        case achCode
        case achHolder
        case achHolderType
        case achRouting
        case device
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .card(data):
            try c.encode(PayabliTokenizationMethod.card.rawValue, forKey: .method)
            try c.encode(data.normalizedExpiration(), forKey: .cardexp)
            try c.encode(data.cardholderName.trimmed, forKey: .cardHolder)
            try c.encode(data.cardNumber.digitsOnly, forKey: .cardnumber)
            try c.encodeIfPresent(data.cvv.map(\.digitsOnly)?.nilIfEmpty, forKey: .cardcvv)
            try c.encode(data.billingZip.trimmed, forKey: .cardzip)

        case let .ach(data):
            try c.encode(PayabliTokenizationMethod.ach.rawValue, forKey: .method)
            try c.encode(data.accountNumber.digitsOnly, forKey: .achAccount)
            try c.encode(data.accountType.rawValue, forKey: .achAccountType)
            try c.encode(data.holderName.trimmed, forKey: .achHolder)
            try c.encode(data.routingNumber.digitsOnly, forKey: .achRouting)
            try c.encode((data.secCode ?? .web).rawValue, forKey: .achCode)
            try c.encodeIfPresent(data.holderType?.rawValue, forKey: .achHolderType)
            try c.encodeIfPresent(data.device.map(\.trimmed)?.nilIfEmpty, forKey: .device)
        }
    }
}

extension PayabliTokenizationPaymentMethod {
    func validate(_ validation: PayabliTokenizationValidation) throws {
        switch self {
        case let .card(data):
            try data.validate(validation)
        case let .ach(data):
            try data.validate(validation)
        }
    }
}

extension PayabliCardTokenizationData {
    func validate(_ validation: PayabliTokenizationValidation) throws {
        let digits = cardNumber.digitsOnly
        guard (12 ... 19).contains(digits.count) else {
            throw PayabliTokenizationError.invalidInput("Card number must be 12 to 19 digits.")
        }
        if validation.requiresLuhnCheck, !Self.passesLuhn(digits) {
            throw PayabliTokenizationError.invalidInput("Card number failed validation.")
        }
        _ = try normalizedExpiration()
        guard !cardholderName.trimmed.isEmpty else {
            throw PayabliTokenizationError.invalidInput("Cardholder name is required.")
        }
        guard !billingZip.trimmed.isEmpty else {
            throw PayabliTokenizationError.invalidInput("Card ZIP code is required.")
        }
        if let cvv = cvv?.digitsOnly, !cvv.isEmpty, !(3 ... 4).contains(cvv.count) {
            throw PayabliTokenizationError.invalidInput("CVV must be 3 or 4 digits.")
        }
    }

    func normalizedExpiration() throws -> String {
        let digits = expiration.digitsOnly
        guard digits.count == 4 || digits.count == 6 else {
            throw PayabliTokenizationError.invalidInput("Expiration must be in MMYY or MM/YY format.")
        }
        let monthPrefix = String(digits.prefix(2))
        guard let month = Int(monthPrefix), (1 ... 12).contains(month) else {
            throw PayabliTokenizationError.invalidInput("Expiration month must be between 01 and 12.")
        }
        let year = digits.count == 4 ? String(digits.suffix(2)) : String(digits.suffix(2))
        return "\(monthPrefix)/\(year)"
    }

    static func passesLuhn(_ digits: String) -> Bool {
        let reversed = digits.reversed().compactMap { Int(String($0)) }
        guard reversed.count == digits.count else { return false }

        let sum = reversed.enumerated().reduce(0) { partial, pair in
            let (index, digit) = pair
            guard index % 2 == 1 else { return partial + digit }
            let doubled = digit * 2
            return partial + (doubled > 9 ? doubled - 9 : doubled)
        }
        return sum % 10 == 0
    }
}

extension PayabliACHTokenizationData {
    func validate(_ validation: PayabliTokenizationValidation) throws {
        let account = accountNumber.digitsOnly
        guard (4 ... 17).contains(account.count) else {
            throw PayabliTokenizationError.invalidInput("ACH account number must be 4 to 17 digits.")
        }
        let routing = routingNumber.digitsOnly
        guard routing.count == 9 else {
            throw PayabliTokenizationError.invalidInput("ACH routing number must be 9 digits.")
        }
        if validation.validatesACHRoutingChecksum, !Self.passesABAChecksum(routing) {
            throw PayabliTokenizationError.invalidInput("ACH routing number failed validation.")
        }
        guard !holderName.trimmed.isEmpty else {
            throw PayabliTokenizationError.invalidInput("ACH account holder is required.")
        }
        let allowed = holderName.range(
            of: #"^[A-Za-z0-9 .'\-]+$"#,
            options: .regularExpression
        ) != nil
        guard allowed else {
            throw PayabliTokenizationError.invalidInput("ACH holder contains unsupported characters.")
        }
    }

    private static func passesABAChecksum(_ routing: String) -> Bool {
        let digits = routing.compactMap { Int(String($0)) }
        guard digits.count == 9 else { return false }
        let weights = [3, 7, 1, 3, 7, 1, 3, 7, 1]
        let sum = zip(digits, weights).reduce(0) { $0 + ($1.0 * $1.1) }
        return sum % 10 == 0
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var digitsOnly: String {
        filter(\.isNumber)
    }

    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return Int(string)
        }
        return nil
    }

    func decodeLossyInt64IfPresent(forKey key: Key) -> Int64? {
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return value
        }
        if let string = try? decodeIfPresent(String.self, forKey: key) {
            return Int64(string)
        }
        return nil
    }
}

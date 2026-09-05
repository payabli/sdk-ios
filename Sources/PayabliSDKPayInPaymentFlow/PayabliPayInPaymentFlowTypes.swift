import Foundation
import PayabliSDKCore

public enum PayabliPayInPaymentFlowOperation: String, CaseIterable, Identifiable, Sendable, Equatable {
    case storePaymentMethod
    case capture
    case authorize

    public var id: String {
        rawValue
    }
}

public enum PayabliPayInPaymentFlowAuthorizationMethod: String, CaseIterable, Identifiable, Sendable, Equatable {
    case card

    public var id: String {
        rawValue
    }
}

public enum PayabliPayInPaymentFlowResultKind: String, Sendable, Equatable {
    case storedPaymentMethod
    case transaction
}

public enum PayabliPayInPaymentFlowStoredMethodType: String, CaseIterable, Identifiable, Codable, Sendable {
    case card
    case ach
    case wallet

    public var id: String {
        rawValue
    }
}

public enum PayabliPayInPaymentFlowStoredUsageType: String, CaseIterable, Identifiable, Codable, Sendable {
    case unscheduled
    case subscription
    case recurring

    public var id: String {
        rawValue
    }
}

public struct PayabliPayInPaymentFlowCardMethod: Sendable {
    public let data: PayabliPayInPaymentFlowCardData
    public let initiator: String?
    public let saveIfSuccess: Bool?

    public init(
        data: PayabliPayInPaymentFlowCardData,
        initiator: String? = "payor",
        saveIfSuccess: Bool? = nil
    ) {
        self.data = data
        self.initiator = initiator
        self.saveIfSuccess = saveIfSuccess
    }
}

public struct PayabliPayInPaymentFlowACHMethod: Sendable {
    public let data: PayabliPayInPaymentFlowACHData

    public init(data: PayabliPayInPaymentFlowACHData) {
        self.data = data
    }
}

public struct PayabliPayInPaymentFlowStoredMethod: Sendable {
    public let method: PayabliPayInPaymentFlowStoredMethodType
    public let storedMethodId: String
    public let storedMethodUsageType: PayabliPayInPaymentFlowStoredUsageType?
    public let initiator: String?

    public init(
        method: PayabliPayInPaymentFlowStoredMethodType,
        storedMethodId: String,
        storedMethodUsageType: PayabliPayInPaymentFlowStoredUsageType? = .unscheduled,
        initiator: String? = "payor"
    ) {
        self.method = method
        self.storedMethodId = storedMethodId
        self.storedMethodUsageType = storedMethodUsageType
        self.initiator = initiator
    }
}

public struct PayabliPayInPaymentFlowCloudMethod: Sendable {
    public let device: String
    public let saveIfSuccess: Bool?

    public init(device: String, saveIfSuccess: Bool? = nil) {
        self.device = device
        self.saveIfSuccess = saveIfSuccess
    }
}

public struct PayabliPayInPaymentFlowCheckMethod: Sendable {
    public let holderName: String

    public init(holderName: String) {
        self.holderName = holderName
    }
}

public enum PayabliPayInPaymentFlowPaymentMethod: Sendable {
    case card(PayabliPayInPaymentFlowCardMethod)
    case ach(PayabliPayInPaymentFlowACHMethod)
    case stored(PayabliPayInPaymentFlowStoredMethod)
    case cloud(PayabliPayInPaymentFlowCloudMethod)
    case check(PayabliPayInPaymentFlowCheckMethod)
    case cash

    public var method: String {
        switch self {
        case .card:
            return "card"
        case .ach:
            return "ach"
        case let .stored(stored):
            return stored.method.rawValue
        case .cloud:
            return "cloud"
        case .check:
            return "check"
        case .cash:
            return "cash"
        }
    }

    var authorizationMethod: PayabliPayInPaymentFlowAuthorizationMethod? {
        switch self {
        case .card:
            return .card
        case .ach, .stored, .cloud, .check, .cash:
            return nil
        }
    }
}

public struct PayabliPayInPaymentFlowPaymentDetails: Codable, Sendable, Equatable {
    public let totalAmount: Double
    public let serviceFee: Double?
    public let currency: String?
    public let checkNumber: String?
    public let checkUniqueId: String?

    public init(
        totalAmount: Double,
        serviceFee: Double? = nil,
        currency: String? = nil,
        checkNumber: String? = nil,
        checkUniqueId: String? = nil
    ) {
        self.totalAmount = totalAmount
        self.serviceFee = serviceFee
        self.currency = currency
        self.checkNumber = checkNumber
        self.checkUniqueId = checkUniqueId
    }
}

extension PayabliPayInPaymentFlowPaymentDetails {
    var payabliViewModelSignature: String {
        [
            "totalAmount:\(totalAmount)",
            "serviceFee:\(serviceFee.map { "\($0)" } ?? "")",
            "currency:\(currency ?? "")",
            "checkNumber:\(checkNumber ?? "")",
            "checkUniqueId:\(checkUniqueId ?? "")"
        ]
        .joined(separator: ",")
    }
}

public struct PayabliPayInPaymentFlowRequest: Sendable {
    public let paymentDetails: PayabliPayInPaymentFlowPaymentDetails
    public let paymentMethod: PayabliPayInPaymentFlowPaymentMethod
    public let accountId: String?
    public let customerData: PayabliPayInPaymentFlowCustomerData?
    public let ipAddress: String?
    public let orderDescription: String?
    public let orderId: String?
    public let source: String?
    public let subdomain: String?
    public let subscriptionId: Int64?
    public let idempotencyKey: String?
    public let achValidation: Bool?
    public let forceCustomerCreation: Bool?
    public let validation: PayabliPayInPaymentFlowValidation

    public init(
        paymentDetails: PayabliPayInPaymentFlowPaymentDetails,
        paymentMethod: PayabliPayInPaymentFlowPaymentMethod,
        accountId: String? = nil,
        customerData: PayabliPayInPaymentFlowCustomerData? = nil,
        ipAddress: String? = nil,
        orderDescription: String? = nil,
        orderId: String? = nil,
        source: String? = nil,
        subdomain: String? = nil,
        subscriptionId: Int64? = nil,
        idempotencyKey: String? = nil,
        achValidation: Bool? = nil,
        forceCustomerCreation: Bool? = nil,
        validation: PayabliPayInPaymentFlowValidation = .default
    ) {
        self.paymentDetails = paymentDetails
        self.paymentMethod = paymentMethod
        self.accountId = accountId
        self.customerData = customerData
        self.ipAddress = ipAddress
        self.orderDescription = orderDescription
        self.orderId = orderId
        self.source = source
        self.subdomain = subdomain
        self.subscriptionId = subscriptionId
        self.idempotencyKey = idempotencyKey
        self.achValidation = achValidation
        self.forceCustomerCreation = forceCustomerCreation
        self.validation = validation
    }
}

// Public API keeps the PayInPaymentFlow namespace for discoverability.
// swiftlint:disable:next type_name
public struct PayabliPayInPaymentFlowRequestConfiguration: Sendable {
    public let paymentDetails: PayabliPayInPaymentFlowPaymentDetails
    public let accountId: String?
    public let customerData: PayabliPayInPaymentFlowCustomerData?
    public let ipAddress: String?
    public let orderDescription: String?
    public let orderId: String?
    public let source: String?
    public let subdomain: String?
    public let subscriptionId: Int64?
    public let idempotencyKey: String?
    public let achValidation: Bool?
    public let forceCustomerCreation: Bool?
    public let validation: PayabliPayInPaymentFlowValidation

    public init(
        paymentDetails: PayabliPayInPaymentFlowPaymentDetails,
        accountId: String? = nil,
        customerData: PayabliPayInPaymentFlowCustomerData? = nil,
        ipAddress: String? = nil,
        orderDescription: String? = nil,
        orderId: String? = nil,
        source: String? = nil,
        subdomain: String? = nil,
        subscriptionId: Int64? = nil,
        idempotencyKey: String? = nil,
        achValidation: Bool? = nil,
        forceCustomerCreation: Bool? = nil,
        validation: PayabliPayInPaymentFlowValidation = .default
    ) {
        self.paymentDetails = paymentDetails
        self.accountId = accountId
        self.customerData = customerData
        self.ipAddress = ipAddress
        self.orderDescription = orderDescription
        self.orderId = orderId
        self.source = source
        self.subdomain = subdomain
        self.subscriptionId = subscriptionId
        self.idempotencyKey = idempotencyKey
        self.achValidation = achValidation
        self.forceCustomerCreation = forceCustomerCreation
        self.validation = validation
    }

    public func request(
        paymentMethod: PayabliPayInPaymentFlowPaymentMethod,
        customerData formCustomerData: PayabliPayInPaymentFlowCustomerData? = nil,
        orderDescription formOrderDescription: String? = nil
    ) -> PayabliPayInPaymentFlowRequest {
        PayabliPayInPaymentFlowRequest(
            paymentDetails: paymentDetails,
            paymentMethod: paymentMethod,
            accountId: accountId,
            customerData: mergedCustomerData(formCustomerData),
            ipAddress: ipAddress,
            orderDescription: formOrderDescription?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty ?? orderDescription,
            orderId: orderId,
            source: source,
            subdomain: subdomain,
            subscriptionId: subscriptionId,
            idempotencyKey: idempotencyKey,
            achValidation: achValidation,
            forceCustomerCreation: forceCustomerCreation,
            validation: validation
        )
    }

    private func mergedCustomerData(
        _ formCustomerData: PayabliPayInPaymentFlowCustomerData?
    ) -> PayabliPayInPaymentFlowCustomerData? {
        guard var merged = customerData else {
            return formCustomerData
        }
        merged.payabliCaptureMerge(formCustomerData)
        return merged.payabliCaptureHasAnyValue ? merged : nil
    }
}

extension PayabliPayInPaymentFlowRequestConfiguration {
    var payabliViewModelSignature: String {
        [
            "paymentDetails:\(paymentDetails.payabliViewModelSignature)",
            "accountId:\(accountId ?? "")",
            "customerData:\(customerData.payabliJSONSignature)",
            "ipAddress:\(ipAddress ?? "")",
            "orderDescription:\(orderDescription ?? "")",
            "orderId:\(orderId ?? "")",
            "source:\(source ?? "")",
            "subdomain:\(subdomain ?? "")",
            "subscriptionId:\(subscriptionId.map { "\($0)" } ?? "")",
            "idempotencyKey:\(idempotencyKey ?? "")",
            "achValidation:\(achValidation.map { "\($0)" } ?? "")",
            "forceCustomerCreation:\(forceCustomerCreation.map { "\($0)" } ?? "")",
            "validation:\(validation.payabliViewModelSignature)"
        ]
        .joined(separator: "|")
    }
}

public struct PayabliPayInPaymentFlowAuthorizedRequest: Sendable {
    public let transId: String
    public let paymentDetails: PayabliPayInPaymentFlowPaymentDetails

    /// The key this capture sends, or nil to have one minted for the attempt.
    ///
    /// This call moves money, so a response lost on the way back leaves the outcome open. Supplying a
    /// key lets a caller resend the same capture rather than risk a second partial one; a repeat inside
    /// the service's window is refused rather than executed, and the first response is not replayed.
    public let idempotencyKey: String?

    public init(
        transId: String,
        paymentDetails: PayabliPayInPaymentFlowPaymentDetails,
        idempotencyKey: String? = nil
    ) {
        self.transId = transId
        self.paymentDetails = paymentDetails
        self.idempotencyKey = idempotencyKey
    }
}

public struct PayabliPayInPaymentFlowFailure: Codable, Sendable, Equatable {
    public let code: String?
    public let reason: String?
    public let explanation: String?
    public let action: String?
    public let status: Int?
    public let detail: String?
    public let httpStatusCode: Int?

    public init(
        code: String? = nil,
        reason: String? = nil,
        explanation: String? = nil,
        action: String? = nil,
        status: Int? = nil,
        detail: String? = nil,
        httpStatusCode: Int? = nil
    ) {
        self.code = code
        self.reason = reason
        self.explanation = explanation
        self.action = action
        self.status = status
        self.detail = detail
        self.httpStatusCode = httpStatusCode
    }

    public var reasonText: String {
        explanation?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
            ?? reason?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
            ?? detail?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
            ?? "Unable to process payment capture."
    }

    public var detailText: String? {
        action?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
    }
}

public struct PayabliPayInPaymentFlowResult: Sendable, Equatable {
    public let kind: PayabliPayInPaymentFlowResultKind
    public let code: String
    public let reason: String?
    public let explanation: String?
    public let action: String?
    public let transaction: PayabliPayInPaymentFlowTransaction?
    public let storedPaymentMethod: PayabliPayInPaymentFlowStoredPaymentMethod?
    public let apiResponse: PayabliPayInPaymentFlowAPIResponse?

    public init(apiResponse: PayabliPayInPaymentFlowAPIResponse) {
        kind = .transaction
        self.code = apiResponse.code
        self.reason = apiResponse.reason
        self.explanation = apiResponse.explanation
        self.action = apiResponse.action
        transaction = apiResponse.data
        storedPaymentMethod = nil
        self.apiResponse = apiResponse
    }

    public init(storedPaymentMethod: PayabliPayInPaymentFlowStoredPaymentMethod) {
        kind = .storedPaymentMethod
        code = storedPaymentMethod.resultCode.map(String.init) ?? "1"
        reason = storedPaymentMethod.resultText ?? storedPaymentMethod.responseText
        explanation = nil
        action = nil
        transaction = nil
        self.storedPaymentMethod = storedPaymentMethod
        apiResponse = nil
    }
}

public struct PayabliPayInPaymentFlowAPIResponse: Codable, Sendable, Equatable {
    public let code: String
    public let reason: String?
    public let explanation: String?
    public let action: String?
    public let data: PayabliPayInPaymentFlowTransaction?
    public let token: String?

    public init(
        code: String,
        reason: String? = nil,
        explanation: String? = nil,
        action: String? = nil,
        data: PayabliPayInPaymentFlowTransaction? = nil,
        token: String? = nil
    ) {
        self.code = code
        self.reason = reason
        self.explanation = explanation
        self.action = action
        self.data = data
        self.token = token
    }

    public var isApproved: Bool {
        code.hasPrefix("A")
    }

    public func failure(httpStatusCode: Int? = nil) -> PayabliPayInPaymentFlowFailure {
        PayabliPayInPaymentFlowFailure(
            code: code,
            reason: reason,
            explanation: explanation,
            action: action,
            httpStatusCode: httpStatusCode
        )
    }
}

public struct PayabliPayInPaymentFlowTransaction: Codable, Sendable, Equatable {
    public let paymentTransId: String?
    public let gatewayTransId: String?
    public let orderId: String?
    public let method: String?
    public let transStatus: Int?
    public let paypointId: Int64?
    public let totalAmount: Double?
    public let netAmount: Double?
    public let feeAmount: Double?
    public let settlementStatus: Int?
    public let operation: String?
    public let responseData: PayabliPayInPaymentFlowResponseData?
    public let source: String?
    public let isValidatedACH: Bool?
    public let transactionTime: String?
    public let achSecCode: String?
    public let achHolderType: String?
    public let ipAddress: String?
    public let walletType: String?

    public init(
        paymentTransId: String? = nil,
        gatewayTransId: String? = nil,
        orderId: String? = nil,
        method: String? = nil,
        transStatus: Int? = nil,
        paypointId: Int64? = nil,
        totalAmount: Double? = nil,
        netAmount: Double? = nil,
        feeAmount: Double? = nil,
        settlementStatus: Int? = nil,
        operation: String? = nil,
        responseData: PayabliPayInPaymentFlowResponseData? = nil,
        source: String? = nil,
        isValidatedACH: Bool? = nil,
        transactionTime: String? = nil,
        achSecCode: String? = nil,
        achHolderType: String? = nil,
        ipAddress: String? = nil,
        walletType: String? = nil
    ) {
        self.paymentTransId = paymentTransId
        self.gatewayTransId = gatewayTransId
        self.orderId = orderId
        self.method = method
        self.transStatus = transStatus
        self.paypointId = paypointId
        self.totalAmount = totalAmount
        self.netAmount = netAmount
        self.feeAmount = feeAmount
        self.settlementStatus = settlementStatus
        self.operation = operation
        self.responseData = responseData
        self.source = source
        self.isValidatedACH = isValidatedACH
        self.transactionTime = transactionTime
        self.achSecCode = achSecCode
        self.achHolderType = achHolderType
        self.ipAddress = ipAddress
        self.walletType = walletType
    }
}

public struct PayabliPayInPaymentFlowResponseData: Codable, Sendable, Equatable {
    public let resultCode: String?
    public let resultCodeText: String?
    public let response: String?
    public let responseText: String?
    public let authCode: String?
    public let transactionId: String?
    public let avsResponse: String?
    public let avsResponseText: String?
    public let cvvResponse: String?
    public let cvvResponseText: String?
    public let orderId: String?
    public let responseCode: String?
    public let responseCodeText: String?
    public let customerVaultId: String?
    public let emvAuthResponseData: String?
    public let type: String?

    enum CodingKeys: String, CodingKey {
        case resultCode
        case resultCodeText
        case response
        case responseText = "responsetext"
        case authCode = "authcode"
        case transactionId = "transactionid"
        case avsResponse = "avsresponse"
        case avsResponseText = "avsresponse_text"
        case cvvResponse = "cvvresponse"
        case cvvResponseText = "cvvresponse_text"
        case orderId = "orderid"
        case responseCode = "response_code"
        case responseCodeText = "response_code_text"
        case customerVaultId = "customer_vault_id"
        case emvAuthResponseData = "emv_auth_response_data"
        case type
    }

    public init(
        resultCode: String? = nil,
        resultCodeText: String? = nil,
        response: String? = nil,
        responseText: String? = nil,
        authCode: String? = nil,
        transactionId: String? = nil,
        avsResponse: String? = nil,
        avsResponseText: String? = nil,
        cvvResponse: String? = nil,
        cvvResponseText: String? = nil,
        orderId: String? = nil,
        responseCode: String? = nil,
        responseCodeText: String? = nil,
        customerVaultId: String? = nil,
        emvAuthResponseData: String? = nil,
        type: String? = nil
    ) {
        self.resultCode = resultCode
        self.resultCodeText = resultCodeText
        self.response = response
        self.responseText = responseText
        self.authCode = authCode
        self.transactionId = transactionId
        self.avsResponse = avsResponse
        self.avsResponseText = avsResponseText
        self.cvvResponse = cvvResponse
        self.cvvResponseText = cvvResponseText
        self.orderId = orderId
        self.responseCode = responseCode
        self.responseCodeText = responseCodeText
        self.customerVaultId = customerVaultId
        self.emvAuthResponseData = emvAuthResponseData
        self.type = type
    }
}

extension PayabliPayInPaymentFlowPaymentMethod: Encodable {
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
        case initiator
        case saveIfSuccess
        case storedMethodId
        case storedMethodUsageType
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case let .card(method):
            try c.encode("card", forKey: .method)
            try c.encode(method.data.normalizedCaptureExpiration(), forKey: .cardexp)
            try c.encode(method.data.cardholderName.payabliCaptureTrimmed, forKey: .cardHolder)
            try c.encode(method.data.cardNumber.payabliCaptureDigitsOnly, forKey: .cardnumber)
            try c.encode(method.data.cvv.payabliCaptureDigitsOnly, forKey: .cardcvv)
            try c.encode(method.data.billingZip.payabliCaptureTrimmed, forKey: .cardzip)
            try c.encodeIfPresent(method.initiator?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty, forKey: .initiator)
            try c.encodeIfPresent(method.saveIfSuccess, forKey: .saveIfSuccess)

        case let .ach(method):
            try c.encode("ach", forKey: .method)
            try c.encode(method.data.accountNumber.payabliCaptureDigitsOnly, forKey: .achAccount)
            try c.encode(method.data.accountType.rawValue, forKey: .achAccountType)
            try c.encode(method.data.holderName.payabliCaptureTrimmed, forKey: .achHolder)
            try c.encode(method.data.routingNumber.payabliCaptureDigitsOnly, forKey: .achRouting)
            try c.encode((method.data.secCode ?? .web).rawValue, forKey: .achCode)
            try c.encodeIfPresent(method.data.holderType?.rawValue, forKey: .achHolderType)
            try c.encodeIfPresent(method.data.device?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty, forKey: .device)

        case let .stored(method):
            try c.encode(method.method.rawValue, forKey: .method)
            try c.encode(method.storedMethodId.payabliCaptureTrimmed, forKey: .storedMethodId)
            try c.encodeIfPresent(method.storedMethodUsageType?.rawValue, forKey: .storedMethodUsageType)
            try c.encodeIfPresent(method.initiator?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty, forKey: .initiator)

        case let .cloud(method):
            try c.encode("cloud", forKey: .method)
            try c.encode(method.device.payabliCaptureTrimmed, forKey: .device)
            try c.encodeIfPresent(method.saveIfSuccess, forKey: .saveIfSuccess)

        case let .check(method):
            try c.encode("check", forKey: .method)
            try c.encode(method.holderName.payabliCaptureTrimmed, forKey: .achHolder)

        case .cash:
            try c.encode("cash", forKey: .method)
        }
    }
}

extension PayabliPayInPaymentFlowPaymentMethod {
    func validate(_ validation: PayabliPayInPaymentFlowValidation) throws {
        switch self {
        case let .card(method):
            try PayabliPayInPaymentFlowMethodInput.card(method.data).validate(validation)
        case let .ach(method):
            try PayabliPayInPaymentFlowMethodInput.ach(method.data).validate(validation)
        case let .stored(method):
            guard !method.storedMethodId.payabliCaptureTrimmed.isEmpty else {
                throw PayabliPayInPaymentFlowError.invalidInput("Stored payment method ID is required.")
            }
        case let .cloud(method):
            guard !method.device.payabliCaptureTrimmed.isEmpty else {
                throw PayabliPayInPaymentFlowError.invalidInput("Cloud device is required.")
            }
        case let .check(method):
            guard !method.holderName.payabliCaptureTrimmed.isEmpty else {
                throw PayabliPayInPaymentFlowError.invalidInput("Check account holder is required.")
            }
        case .cash:
            break
        }
    }
}

extension PayabliPayInPaymentFlowPaymentDetails {
    func validate() throws {
        guard totalAmount > 0 else {
            throw PayabliPayInPaymentFlowError.invalidInput("Total amount must be greater than 0.")
        }
        if let serviceFee, serviceFee < 0 {
            throw PayabliPayInPaymentFlowError.invalidInput("Service fee cannot be negative.")
        }
    }
}

private extension PayabliPayInPaymentFlowCardData {
    func normalizedCaptureExpiration() throws -> String {
        let digits = expiration.payabliCaptureDigitsOnly
        guard digits.count == 4 else {
            throw PayabliPayInPaymentFlowError.invalidInput("Expiration must be in MMYY or MM/YY format.")
        }
        let monthPrefix = String(digits.prefix(2))
        guard let month = Int(monthPrefix), (1 ... 12).contains(month) else {
            throw PayabliPayInPaymentFlowError.invalidInput("Expiration month must be between 01 and 12.")
        }
        let year = String(digits.suffix(2))
        return "\(monthPrefix)/\(year)"
    }
}

extension String {
    var payabliCaptureTrimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var payabliCaptureDigitsOnly: String {
        filter(\.isNumber)
    }

    var payabliCaptureNilIfEmpty: String? {
        isEmpty ? nil : self
    }
}

extension PayabliPayInPaymentFlowCustomerData {
    var payabliCaptureHasAnyValue: Bool {
        additionalData?.isEmpty == false
            || billingAddress1?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty != nil
            || billingAddress2?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty != nil
            || billingCity?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty != nil
            || billingCountry?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty != nil
            || billingEmail?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty != nil
            || billingPhone?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty != nil
            || billingState?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty != nil
            || billingZip?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty != nil
            || company?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty != nil
            || customerId != nil
            || customerNumber?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty != nil
            || firstName?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty != nil
            || identifierFields?.isEmpty == false
            || lastName?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty != nil
            || shippingAddress1?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty != nil
            || shippingAddress2?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty != nil
            || shippingCity?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty != nil
            || shippingCountry?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty != nil
            || shippingState?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty != nil
            || shippingZip?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty != nil
    }

    mutating func payabliCaptureMerge(_ override: PayabliPayInPaymentFlowCustomerData?) {
        guard let override else { return }
        additionalData = override.additionalData ?? additionalData
        billingAddress1 = override.billingAddress1 ?? billingAddress1
        billingAddress2 = override.billingAddress2 ?? billingAddress2
        billingCity = override.billingCity ?? billingCity
        billingCountry = override.billingCountry ?? billingCountry
        billingEmail = override.billingEmail ?? billingEmail
        billingPhone = override.billingPhone ?? billingPhone
        billingState = override.billingState ?? billingState
        billingZip = override.billingZip ?? billingZip
        company = override.company ?? company
        customerId = override.customerId ?? customerId
        customerNumber = override.customerNumber ?? customerNumber
        firstName = override.firstName ?? firstName
        identifierFields = override.identifierFields ?? identifierFields
        lastName = override.lastName ?? lastName
        shippingAddress1 = override.shippingAddress1 ?? shippingAddress1
        shippingAddress2 = override.shippingAddress2 ?? shippingAddress2
        shippingCity = override.shippingCity ?? shippingCity
        shippingCountry = override.shippingCountry ?? shippingCountry
        shippingState = override.shippingState ?? shippingState
        shippingZip = override.shippingZip ?? shippingZip
    }

    mutating func payabliCaptureApply<Value>(
        _ keyPath: WritableKeyPath<PayabliPayInPaymentFlowCustomerData, Value?>,
        _ value: Value?
    ) {
        guard let value else { return }
        self[keyPath: keyPath] = value
    }
}

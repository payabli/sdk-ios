import Foundation
import PayabliSDKCore

/// BIN lookup data embedded in transaction results.
public struct PayabliBINData: Decodable, Sendable {
    public let binCardBrand: String?
    public let binCardType: String?
}

/// Payment-data block within an approved transaction response.
public struct PayabliPaymentData: Decodable, Sendable {
    public let maskedAccount: String?
    public let accountType: String?
    public let accountExp: String?
    public let holderName: String?
    public let storedId: String?
    public let initiator: String?
    public let sequence: String?
    public let binData: PayabliBINData?
}

/// Gateway response detail block.
public struct PayabliResponseData: Decodable, Sendable {
    public let resultCode: String?
    public let resultCodeText: String?
    public let authcode: String?
    public let transactionid: String?
    public let avsresponse: String?
    public let cvvresponse: String?
}

/// Customer block in the transaction response.
public struct PayabliCustomerData: Decodable, Sendable {
    public let customerId: Int?
    public let firstName: String?
    public let lastName: String?
}

/// Full transaction data envelope (PRD §8.1.1 "Approved Response" -> `data`).
public struct PayabliTransactionData: Decodable, Sendable {
    public let paymentTransId: String
    public let gatewayTransId: String?
    public let method: String?
    public let totalAmount: Decimal?
    public let netAmount: Decimal?
    public let feeAmount: Decimal?
    public let transStatus: Int?
    public let operation: String?
    public let paymentData: PayabliPaymentData?
    public let responseData: PayabliResponseData?
    public let customer: PayabliCustomerData?
    public let transactionTime: String?
}

/// Returned to the host app on successful `processPayment` / `chargeStoredMethod` calls.
///
/// See PRD FR-12A.4.
public struct PayabliTransactionResult: Sendable {
    public let paymentTransId: String
    public let responseCode: String
    public let responseReason: String?
    public let explanation: String?
    public let action: String?
    public let authCode: String?
    public let maskedAccount: String?
    public let accountType: String?
    /// Set when `saveIfSuccess` was true and the transaction was approved (FR-12C.6).
    public let methodReferenceId: String?
    public let data: PayabliTransactionData

    public init(from envelope: PayabliV2TransactionEnvelope) {
        self.responseCode = envelope.code
        self.responseReason = envelope.reason
        self.explanation = envelope.explanation
        self.action = envelope.action

        // Envelope.data is non-nil on approved paths (we only construct on approval).
        let txData = envelope.data!
        self.data = txData
        self.paymentTransId = txData.paymentTransId
        self.authCode = txData.responseData?.authcode
        self.maskedAccount = txData.paymentData?.maskedAccount
        self.accountType = txData.paymentData?.accountType
        self.methodReferenceId = txData.paymentData?.storedId
    }
}

/// The v2 envelope used by getpaid transaction responses.
///
/// Aliased here so getpaid-specific tests can decode without a generic parameter.
public struct PayabliV2TransactionEnvelope: Decodable, Sendable {
    public let code: String
    public let reason: String?
    public let explanation: String?
    public let action: String?
    public let data: PayabliTransactionData?
    public let token: String?

    public var isApproved: Bool { code.hasPrefix("A") }
    public var isDeclined: Bool { code.hasPrefix("D") }
}

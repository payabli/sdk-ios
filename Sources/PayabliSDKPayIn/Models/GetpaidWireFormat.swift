import Foundation
import PayabliSDKCore

// MARK: - Request payloads (PRD §8.1.1)

struct GetpaidPaymentDetails: Encodable {
    let totalAmount: Decimal
    let serviceFee: Decimal
    let currency: String?
    let categories: [PayabliCategory]?
    let invoiceData: PayabliInvoiceData?
}

struct GetpaidCardMethod: Encodable {
    let method: String
    let cardnumber: String
    let cardexp: String
    let cardHolder: String
    let cardcvv: String
    let cardzip: String
    let initiator: String
    let saveIfSuccess: Bool

    init(payload: CardTokenizationPayload, saveIfSuccess: Bool, initiator: PaymentInitiator) {
        self.method = "card"
        self.cardnumber = payload.cardnumber
        self.cardexp = payload.cardexp
        self.cardHolder = payload.cardHolder
        self.cardcvv = payload.cardcvv
        self.cardzip = payload.cardzip
        self.initiator = initiator.apiValue
        self.saveIfSuccess = saveIfSuccess
    }
}

struct GetpaidACHMethod: Encodable {
    let method: String
    let achAccount: String
    let achRouting: String
    let achAccountType: ACHAccountType
    let achHolder: String
    let achHolderType: ACHHolderType
    let achCode: String
    let initiator: String
    let saveIfSuccess: Bool

    init(payload: ACHTokenizationPayload, saveIfSuccess: Bool, initiator: PaymentInitiator) {
        self.method = "ach"
        self.achAccount = payload.achAccount
        self.achRouting = payload.achRouting
        self.achAccountType = payload.achAccountType
        self.achHolder = payload.achHolder
        self.achHolderType = payload.achHolderType
        self.achCode = payload.achCode
        self.initiator = initiator.apiValue
        self.saveIfSuccess = saveIfSuccess
    }
}

struct GetpaidStoredMethod: Encodable {
    let method: String          // "card" | "ach"
    let storedMethodId: String
    let initiator: String
    let storedMethodUsageType: String?
}

struct GetpaidApplePayMethod: Encodable {
    let method: String
    let applePayToken: String
    let applePayNetwork: String?
    let applePayDisplayName: String?
    let initiator: String
    let saveIfSuccess: Bool

    init(token: ApplePayToken, saveIfSuccess: Bool, initiator: PaymentInitiator) {
        self.method = "applepay"
        self.applePayToken = token.paymentData.base64EncodedString()
        self.applePayNetwork = token.network
        self.applePayDisplayName = token.displayName
        self.initiator = initiator.apiValue
        self.saveIfSuccess = saveIfSuccess
    }
}

struct GetpaidRequest<Method: Encodable>: Encodable {
    let entryPoint: String
    let ipaddress: String?
    let customerData: CustomerDataBlock
    let paymentDetails: GetpaidPaymentDetails
    let paymentMethod: Method
}

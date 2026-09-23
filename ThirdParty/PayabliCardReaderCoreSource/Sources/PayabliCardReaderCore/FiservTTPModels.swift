//  FiservTTP
//
//  Copyright (c) 2022 - 2025 Fiserv, Inc.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in
//  all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
//  THE SOFTWARE.

import Foundation

extension Optional where Wrapped == String {
    var nilIfEmpty: String? {
        guard let strongSelf = self else {
            return nil
        }
        let safeString = strongSelf.trimmingCharacters(in: .whitespacesAndNewlines)
        return safeString.isEmpty ? nil : safeString
    }
}

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// ERROR WRAPPER

package struct FiservTTPErrorWrapper: Identifiable {
    package let id: UUID
    package let error: FiservTTPCardReaderError
    package let guidance: String

    package init(id: UUID = UUID(), error: FiservTTPCardReaderError, guidance: String) {
        self.id = id
        self.error = error
        self.guidance = guidance
    }
}

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// CHARGE RESPONSE WRAPPER

package struct FiservTTPResponseWrapper: Identifiable {
    package let id: UUID
    package let title: String
    
    package let responseString: String?
    
    package init(id: UUID = UUID(), title: String, responseString: String? = nil) {
        
        self.id = id
        self.title = title
        self.responseString = responseString
    }
}

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// CONFIGURATION

package struct FiservTTPConfig {
    package let secretKey: String
    package let apiKey: String
    package let environment: FiservTTPEnvironment
    package let currencyCode: String
    package let merchantId: String
    package let appleTtpMerchantId: String?
    package let merchantName: String
    package let merchantCategoryCode: String
    package let terminalId: String
    package let terminalProfileId: String

    /**
     Primary Configuration used for all requests

     - parameter secretKey:             Your provided Fiserv Secret Key
     - parameter apiKey:                Your provided Fiserv Api Key
     - parameter environment:           The destination for network requests (Sandbox or Production)
     - parameter currencyCode:          The Currency Code used for transactions
     - parameter merchantId:            Your MerchantId
     - parameter appleTtpMerchantId           Your apple TTP MerchantId (Optional)
     - parameter merchantName:          Your Merchant Name
     - parameter merchantCategoryCode:  Your MerchantId Category Code
     - parameter terminalId:            Your TerminalId
     - parameter terminalProfileId:     Your Terminal Profile Id
     
     - returns: FiservTTPConfig struct that will be used throughout the app lifecycle
     */
    package init(secretKey: String,
                apiKey: String,
                environment: FiservTTPEnvironment,
                currencyCode: String,
                merchantId: String,
                appleTtpMerchantId: String? = nil,
                merchantName: String,
                merchantCategoryCode: String,
                terminalId: String,
                terminalProfileId: String) {
        
        self.secretKey = secretKey
        self.apiKey = apiKey
        self.environment = environment
        self.currencyCode = currencyCode
        self.merchantId = merchantId
        self.appleTtpMerchantId = appleTtpMerchantId.nilIfEmpty
        self.merchantName = merchantName
        self.merchantCategoryCode = merchantCategoryCode
        self.terminalId = terminalId
        self.terminalProfileId = terminalProfileId
    }
}

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// AUTHENTICATION TOKEN REQUEST AND RESPONSE MODEL

internal struct FiservTTPMerchantDetails: Codable {
    let merchantId: String
    let terminalId: String
}

internal struct FiservTTPDynamicDescriptors: Codable {
    let mcc: String
    let merchantName: String
}

internal struct FiservTTPTokenRequest: Codable {
    let terminalProfileId: String
    let channel: String
    let accessTokenTimeToLive: Int
    let dynamicDescriptors: FiservTTPDynamicDescriptors
    let merchantDetails: FiservTTPMerchantDetails
    let appleTtpMerchantId: String?
}

package struct FiservTTPTokenResponse: Codable {
    package let gatewayResponse: FiservTTPChargeResponseGatewayResponse
    package let accessToken: String
    package let accessTokenTimeToLive: Int
    package let accessTokenType: String
}

// VALIDATE RESPONSE
package struct FiservTTPValidateCardResponse: Codable {
    
    let id: String
    package let generalCardData: String?
    package let paymentCardData: String?
}

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// INQUIRY REQUEST MODEL

internal struct FiservTTPInquiryReferenceTransactionDetails: Codable {
    
    let referenceTransactionId: String?
    let referenceMerchantTransactionId: String?
    let referenceMerchantOrderId: String?
    let referenceOrderId: String?
    let referenceClientRequestId: String?
    
    internal init(referenceTransactionId: String? = nil,
                  referenceMerchantTransactionId: String? = nil,
                  referenceMerchantOrderId: String? = nil,
                  referenceOrderId: String? = nil,
                  referenceClientRequestId: String? = nil) {
        
        self.referenceTransactionId = referenceTransactionId
        self.referenceMerchantTransactionId = referenceMerchantTransactionId
        self.referenceMerchantOrderId = referenceMerchantOrderId
        self.referenceOrderId = referenceOrderId
        self.referenceClientRequestId = referenceClientRequestId
    }
}

internal struct FiservTTPInquiryMerchantDetails: Codable {
    
    let tokenType: String?
    let storeId: String?
    let siteId: String?
    let terminalId: String?
    let merchantId: String?
    
    internal init(tokenType: String? = nil,
                  storeId: String? = nil,
                  siteId: String? = nil,
                  terminalId: String? = nil,
                  merchantId: String? = nil) {
        
        self.tokenType = tokenType
        self.storeId = storeId
        self.siteId = siteId
        self.terminalId = terminalId
        self.merchantId = merchantId
    }
}

internal struct FiservTTPInquiryRequest: Codable {
    let referenceTransactionDetails: FiservTTPInquiryReferenceTransactionDetails
    let merchantDetails: FiservTTPInquiryMerchantDetails
}

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// CHARGES REQUEST AND RESPONSE MODEL

internal struct FiservTTPChargeRequestAmount: Codable {
    let total: Decimal
    let currency: String
}

internal struct FiservTTPChargeRequestSource: Codable {
    let sourceType: String
    let generalCardData: String
    let paymentCardData: String
    let cardReaderId: String
    let cardReaderTransactionId: String
    let appleTtpMerchantId: String?
}

internal struct FiservTTPChargeRequestTransactionDetails: Codable {
    let captureFlag: Bool
    let merchantOrderId: String?
    let merchantTransactionId: String?
    let merchantInvoiceNumber: String?
}

internal struct FiservTTPChargeRequestPosFeatures: Codable {
    let pinAuthenticationCapability: String
    let terminalEntryCapability: String
}

internal struct FiservTTPChargeRequestAdditionalDataCommon: Codable {
    let origin: FiservTTPChargeRequestAdditionalDataCommonProcessors
}

internal struct FiservTTPChargeRequestAdditionalDataCommonProcessors: Codable {
    let processors: FiservTTPChargeRequestAdditionalDataCommonProcessor
}

internal struct FiservTTPChargeRequestAdditionalDataCommonProcessor: Codable {
    let processorName: String
    let processingPlatform: String
    let settlementPlatform: String
    let priority: String
}

internal struct FiservTTPChargeRequestPosHardwareAndSoftware: Codable {
    let softwareApplicationName: String
    let softwareVersionNumber: String
    let hardwareVendorIdentifier: String
}

internal struct FiservTTPChargeRequestDataEntrySource: Codable {
    let dataEntrySource: String
    let posFeatures: FiservTTPChargeRequestPosFeatures
    let posHardwareAndSoftware : FiservTTPChargeRequestPosHardwareAndSoftware
}

internal struct FiservTTPChargeRequestTransactionInteraction: Codable {
    let origin: String
    let posEntryMode: String
    let posConditionCode: String
    let additionalPosInformation: FiservTTPChargeRequestDataEntrySource
}

internal struct FiservTTPChargeRequest: Codable {
    let amount: FiservTTPChargeRequestAmount
    let source: FiservTTPChargeRequestSource
    let transactionDetails: FiservTTPChargeRequestTransactionDetails
    let transactionInteraction: FiservTTPChargeRequestTransactionInteraction
    let merchantDetails: FiservTTPMerchantDetails
    let additionalDataCommon: FiservTTPChargeRequestAdditionalDataCommon
}

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// VOID REQUEST AND RESPONSE MODEL

internal struct FiservTTPVoidRequestAmount: Codable {
    let total: Decimal
    let currency: String
}

internal struct FiservTTPVoidMerchantDetails: Codable {
    let terminalId: String
    let merchantId: String
}

internal struct FiservTTPVoidReferenceTransactionDetails: Codable {
    let referenceTransactionId: String?
    let referenceMerchantTransactionId: String?
    let referenceTransactionType: String
    
    internal init(referenceTransactionId: String? = nil,
                  referenceMerchantTransactionId: String? = nil,
                  referenceTransactionType: String) {
        self.referenceTransactionId = referenceTransactionId
        self.referenceMerchantTransactionId = referenceMerchantTransactionId
        self.referenceTransactionType = referenceTransactionType
    }
}

internal struct FiservTTPVoidRequest: Codable {
    let referenceTransactionDetails: FiservTTPVoidReferenceTransactionDetails
    let amount: FiservTTPVoidRequestAmount
    let merchantDetails: FiservTTPVoidMerchantDetails
}

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// REFUND REQUEST AND RESPONSE MODEL

internal struct FiservTTPRefundRequestAmount: Codable {
    let total: Decimal
    let currency: String
}

internal struct FiservTTPRefundMerchantDetails: Codable {
    let terminalId: String
    let merchantId: String
}

internal struct FiservTTPRefundReferenceTransactionDetails: Codable {
    let referenceTransactionId: String?
    let referenceMerchantTransactionId: String?
    let referenceTransactionType: String
    
    internal init(referenceTransactionId: String? = nil,
                  referenceMerchantTransactionId: String? = nil,
                  referenceTransactionType: String) {
        self.referenceTransactionId = referenceTransactionId
        self.referenceMerchantTransactionId = referenceMerchantTransactionId
        self.referenceTransactionType = referenceTransactionType
    }
}

internal struct FiservTTPRefundRequest: Codable {
    let referenceTransactionDetails: FiservTTPRefundReferenceTransactionDetails
    let amount: FiservTTPRefundRequestAmount
    let merchantDetails: FiservTTPRefundMerchantDetails
}

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
// REFUND CARD REQUEST AND RESPONSE MODEL

internal struct FiservTTPRefundCardRequestAmount: Codable {
    let total: Decimal
    let currency: String
}

internal struct FiservTTPRefundCardRequestMerchantDetails: Codable {
    let merchantId: String
    let terminalId: String
}

internal struct FiservTTPRefundCardRequestSource: Codable {
    let sourceType: String
    let generalCardData: String
    let paymentCardData: String
    let cardReaderId: String
    let cardReaderTransactionId: String
    let appleTtpMerchantId: String?
}

internal struct FiservTTPRefundCardRequestPosFeatures: Codable {
    let pinAuthenticationCapability: String
    let terminalEntryCapability: String
}

internal struct FiservTTPRefundCardRequestAdditionalDataCommon: Codable {
    let origin: FiservTTPRefundCardRequestAdditionalDataCommonProcessors
}

internal struct FiservTTPRefundCardRequestAdditionalDataCommonProcessors: Codable {
    let processors: FiservTTPRefundCardRequestAdditionalDataCommonProcessor
}

internal struct FiservTTPRefundCardRequestAdditionalDataCommonProcessor: Codable {
    let processorName: String
    let processingPlatform: String
    let settlementPlatform: String
    let priority: String
}

internal struct FiservTTPRefundCardRequestDataEntrySource: Codable {
    let dataEntrySource: String
    let posFeatures: FiservTTPRefundCardRequestPosFeatures
    let posHardwareAndSoftware : FiservTTPChargeRequestPosHardwareAndSoftware
}

internal struct FiservTTPRefundCardRequestTransactionInteraction: Codable {
    let origin: String
    let posEntryMode: String
    let posConditionCode: String
    let additionalPosInformation: FiservTTPRefundCardRequestDataEntrySource
}

internal struct FiservTTPRefundCardRequestTransactionDetails: Codable {
    let captureFlag: Bool
    let merchantOrderId: String?
    let merchantTransactionId: String?
    let merchantInvoiceNumber: String?
}

internal struct FiservTTPRefundCardRequest: Codable {
    let amount: FiservTTPRefundCardRequestAmount
    let source: FiservTTPRefundCardRequestSource
    let transactionDetails: FiservTTPRefundCardRequestTransactionDetails?
    let referenceTransactionDetails: FiservTTPRefundReferenceTransactionDetails?
    let transactionInteraction: FiservTTPRefundCardRequestTransactionInteraction
    let merchantDetails: FiservTTPRefundCardRequestMerchantDetails
    let additionalDataCommon: FiservTTPRefundCardRequestAdditionalDataCommon
}

// - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -

package struct FiservTTPServerError: Codable {
    package let gatewayResponse: FiservTTPServerErrorGatewayResponse
    package let error: [FiservTTPServerErrorError]?
}

package struct FiservTTPServerErrorGatewayResponse: Codable {
    package let transactionType: String?
    package let transactionState: String?
    package let transactionProcessingDetails: FiservTTPServerErrorTransactionProcessingDetails?
}

package struct FiservTTPServerErrorTransactionProcessingDetails: Codable {
    package let orderId: String?
    package let transactionTimestamp: String?
    package let apiTraceId: String?
    package let clientRequestId: String?
    package let transactionId: String?
}

package struct FiservTTPServerErrorError: Codable {
    package let type: String?
    package let field: String?
    package let code: String?
    package let message: String?
}

package struct FiservTTPPaymentTokenResponse: Codable {
    
    package let tokenData: String
    package let tokenSource: String
    package let tokenResponseCode: String
    package let tokenResponseDescription: String
}

package struct FiservTTPChargeResponse: Codable {
    package let gatewayResponse: FiservTTPChargeResponseGatewayResponse?
    package let source: FiservTTPChargeResponseSource?
    package let paymentReceipt: FiservTTPChargeResponsePaymentReceipt?
    package let transactionDetails: FiservTTPChargeResponseTransactionDetails?
    package let transactionInteraction: FiservTTPChargeResponseTransactionInteraction?
    package let merchantDetails: FiservTTPChargeResponseMerchantDetails?
    package let networkDetails: FiservTTPChargeResponseNetworkDetails?
    package let cardDetails: FiservTTPChargeResponseCardDetails?
    package let paymentTokens: [FiservTTPPaymentTokenResponse]?
    package let error: [FiservTTPServerErrorError]?
}

package struct FiservTTPChargeResponseGatewayResponse: Codable {
    package let transactionType: String?
    package let transactionState: String?
    package let transactionOrigin: String?
    package let transactionProcessingDetails: FiservTTPChargeResponseTransactionProcessingDetails?
}

package struct FiservTTPChargeResponseTransactionProcessingDetails: Codable {
    package let orderId: String?
    package let transactionTimestamp: String?
    package let apiTraceId: String?
    package let clientRequestId: String?
    package let transactionId: String?
    package let apiKey: String?
}

package struct FiservTTPChargeResponseSource: Codable {
    package let sourceType: String?
    package let card: FiservTTPChargeResponseCard?
    package let emvData: String?
    package let generalCardData: String?
}

package struct FiservTTPChargeResponseCard: Codable {
    package let expirationMonth: String?
    package let expirationYear: String?
    package let bin: String?
    package let last4: String?
    package let scheme: String?
}

package struct FiservTTPChargeResponsePaymentReceipt: Codable {
    package let approvedAmount: FiservTTPChargeResponseApprovedAmount?
    package let processorResponseDetails: FiservTTPChargeResponseProcessorResponseDetails?
}

package struct FiservTTPChargeResponseApprovedAmount: Codable {
    package let total: Decimal?
    package let currency: String?
}

extension LosslessStringConvertible {
    var string: String { .init(self) }
}

extension FloatingPoint where Self: LosslessStringConvertible {
    var decimal: Decimal? { Decimal(string: string) }
}

extension FiservTTPChargeResponseApprovedAmount {

    enum CodingKeys: String, CodingKey {
        case total = "total"
        case currency = "currency"
    }

    package init(from decoder: Decoder) throws {

        let container = try decoder.container(keyedBy: CodingKeys.self)

        self.total = try container.decode(Double.self, forKey: .total).decimal ?? .zero

        self.currency = try container.decode(String.self, forKey: .currency)
    }
}

package struct FiservTTPChargeResponseProcessorResponseDetails: Codable {
    package let approvalStatus: String?
    package let approvalCode: String?
    package let referenceNumber: String?
    package let processor: String?
    package let host: String?
    package let networkRouted: String?
    package let networkInternationalId: String?
    package let responseCode: String?
    package let responseMessage: String?
    package let hostResponseCode: String?
    package let hostResponseMessage: String?
    package let responseIndicators: FiservTTPChargeResponseProcessorResponseIndicators?
    package let bankAssociationDetails: FiservTTPChargeResponseBankAssociationDetails?
    package let additionalInfo: [FiservTTPChargeResponseAdditionalInfo]?
}

package struct FiservTTPChargeResponseProcessorResponseIndicators: Codable {
    package let alternateRouteDebitIndicator: Bool?
    package let signatureLineIndicator: Bool?
    package let signatureDebitRouteIndicator: Bool?
}

package struct FiservTTPChargeResponseBankAssociationDetails: Codable {
    package let associationResponseCode: String?
}

package struct FiservTTPChargeResponseAdditionalInfo: Codable {
    package let name: String?
    package let value: String?
}

package struct FiservTTPChargeResponseTransactionDetails: Codable {
    package let captureFlag: Bool?
    package let transactionCaptureType: String?
    package let authentication3DS: Bool?
    package let processingCode: String?
    package let merchantTransactionId: String?
    package let merchantOrderId: String?
    package let merchantInvoiceNumber: String?
    package let createToken: Bool?
    package let retrievalReferenceNumber: String?
}

package struct FiservTTPChargeResponseTransactionInteraction: Codable {
    package let posEntryMode: String?
    package let posConditionCode: String?
    package let additionalPosInformation: FiservTTPChargeResponseAdditionalPosInformation?
    package let authorizationCharacteristicsIndicator: String?
    package let hostPosEntryMode: String?
    package let hostPosConditionCode: String?
}

package struct FiservTTPChargeResponsePosHardwareAndSoftware: Codable {
    let softwareApplicationName: String
    let softwareVersionNumber: String
}

package struct FiservTTPChargeResponseAdditionalPosInformation: Codable {
    package let stan: String?
    package let dataEntrySource: String?
    package let posFeatures: FiservTTPChargeResponsePosFeatures?
    package let posHardwareAndSoftware : FiservTTPChargeResponsePosHardwareAndSoftware?
}

package struct FiservTTPChargeResponsePosFeatures: Codable {
    package let pinAuthenticationCapability: String?
    package let terminalEntryCapability: String?
}

package struct FiservTTPChargeResponseMerchantDetails: Codable {
    package let tokenType: String?
    package let terminalId: String?
    package let merchantId: String?
}

package struct FiservTTPChargeResponseNetworkDetails: Codable {
    package let network: FiservTTPChargeResponseNetwork?
    package let debitNetworkId: String?
    package let networkResponseCode: String?
    package let cardLevelResultCode: String?
    package let validationCode: String?
    package let transactionIdentifier: String?
}

package struct FiservTTPChargeResponseNetwork: Codable {
    package let network: String?
    package let cardAuthenticationResultCode: String?
}

package struct FiservTTPChargeResponseCardDetails: Codable {
    package let recordType: String?
    package let lowBin: String?
    package let highBin: String?
    package let binLength: String?
    package let binDetailPan: String?
    package let issuerBankName: String?
    package let countryCode: String?
    package let detailedCardProduct: String?
    package let detailedCardIndicator: String?
    package let pinSignatureCapability: String?
    package let issuerUpdateYear: String?
    package let issuerUpdateMonth: String?
    package let issuerUpdateDay: String?
    package let regulatorIndicator: String?
    package let cardClass: String?
    package let debitPinlessIndicator: [FiservTTPChargeResponseDebitPinlessIndicator]?
    package let nonMoneyTransferOCTsDomestic: String?
    package let nonMoneyTransferOCTsCrossBorder: String?
    package let onlineGamblingOCTsDomestic: String?
    package let onlineGamblingOCTsCrossBorder: String?
    package let moneyTransferOCTsDomestic: String?
    package let moneyTransferOCTsCrossBorder: String?
    package let fastFundsDomesticMoneyTransfer: String?
    package let fastFundsCrossBorderMoneyTransfer: String?
    package let fastFundsDomesticNonMoneyTransfer: String?
    package let fastFundsCrossBorderNonMoneyTransfer: String?
    package let fastFundsDomesticGambling: String?
    package let fastFundsCrossBorderGambling: String?
    package let productId: String?
    package let accountFundSource: String?
    package let panLengthMin: String?
    package let panLengthMax: String?
}

package struct FiservTTPChargeResponseDebitPinlessIndicator: Codable {
    package let debitNetworkId: String?
    package let pinnedPOS: String?
}


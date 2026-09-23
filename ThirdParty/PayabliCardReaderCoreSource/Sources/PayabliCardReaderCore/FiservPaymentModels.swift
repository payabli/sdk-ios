//  FiservPaymentModels
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

package struct Models {
    
    package struct DynamicDescriptorsRequest: Codable {
        package let merchantCategoryCode: String
        package let merchantName: String
        
        package init(merchantCategoryCode: String, merchantName: String) {
            self.merchantCategoryCode = merchantCategoryCode
            self.merchantName = merchantName
        }
    }
    
    package struct MerchantDetailsRequest: Codable {
        package let merchantId: String
        package let terminalId: String
        
        package init(merchantId: String, terminalId: String) {
            self.merchantId = merchantId
            self.terminalId = terminalId
        }
    }
    
    package struct SourceRequest: Codable {
        package let sourceType: String
        package let generalCardData: String?
        package let paymentCardData: String?
        package let cardReaderId: String?
        package let cardReaderTransactionId: String?
        package let appleTtpMerchantId: String?
        
        package init(sourceType: String,
                    generalCardData: String?,
                    paymentCardData: String?,
                    cardReaderId: String?,
                    cardReaderTransactionId: String?,
                    appleTtpMerchantId: String?) {
            
            self.sourceType = sourceType
            self.generalCardData = generalCardData
            self.paymentCardData = paymentCardData
            self.cardReaderId = cardReaderId
            self.cardReaderTransactionId = cardReaderTransactionId
            self.appleTtpMerchantId = appleTtpMerchantId
        }
    }
    
    package struct TransactionDetailsRequest: Codable {
        
        package let merchantTransactionId: String?
        package let merchantOrderId: String?
        package let merchantInvoiceNumber: String?
        package let captureFlag: Bool
        package let createToken: Bool
        
        package init(merchantTransactionId: String? = nil,
                    merchantOrderId: String? = nil,
                    merchantInvoiceNumber: String? = nil,
                    captureFlag: Bool = false,
                    createToken: Bool = false) {
            self.merchantTransactionId = merchantTransactionId
            self.merchantOrderId = merchantOrderId
            self.merchantInvoiceNumber = merchantInvoiceNumber
            self.captureFlag = captureFlag
            self.createToken = createToken
        }
    }
    
    package struct ReferenceTransactionDetailsRequest: Codable {
        
        package let referenceTransactionId: String?
        package let referenceMerchantTransactionId: String?
        package let referenceOrderId: String?
        package let referenceMerchantOrderId: String?
        package let referenceClientRequestId: String?
        
        package init(referenceTransactionId: String? = nil,
                    referenceMerchantTransactionId: String? = nil,
                    referenceOrderId: String? = nil,
                    referenceMerchantOrderId: String? = nil,
                    referenceClientRequestId: String? = nil) {
            
            self.referenceTransactionId = referenceTransactionId
            self.referenceMerchantTransactionId = referenceMerchantTransactionId
            self.referenceOrderId = referenceOrderId
            self.referenceMerchantOrderId = referenceMerchantOrderId
            self.referenceClientRequestId = referenceClientRequestId
        }
    }
    
    // RESPONSE
    package struct TransactionProcessingDetailsResponse: Codable {
        package let orderId: String?
        package let transactionTimestamp: String?
        package let apiTraceId: String?
        package let clientRequestId: String?
        package let transactionId: String?
        package let apiKey: String?
    }

    package struct GatewayResponse: Codable {
        package let transactionType: String?
        package let transactionState: String?
        package let transactionOrigin: String?
        package let transactionProcessingDetails: TransactionProcessingDetailsResponse?
    }
    
    package struct CardResponse: Codable {
        package let expirationMonth: String?
        package let expirationYear: String?
        package let bin: String?
        package let last4: String?
        package let scheme: String?
    }
    
    package struct SourceResponse: Codable {
        package let sourceType: String?
        package let hasBeenDecrypted: Bool?
        package let card: CardResponse?
        package let emvData: String?
        package let generalCardData: String?
    }
    
    // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    // AUTHENTICATION
    
    // REQUEST
    package struct AuthenticateRequest: Codable {
        package let terminalProfileId: String
        package let channel: String
        package let accessTokenTimeToLive: Int
        package let dynamicDescriptorsRequest: Models.DynamicDescriptorsRequest
        package let merchantDetailsRequest: Models.MerchantDetailsRequest
        package let appleTtpMerchantId: String?
        
        package init(terminalProfileId: String,
                    channel: String,
                    accessTokenTimeToLive: Int,
                    dynamicDescriptorsRequest: Models.DynamicDescriptorsRequest,
                    merchantDetailsRequest: MerchantDetailsRequest,
                    appleTtpMerchantId: String?) {

            self.terminalProfileId = terminalProfileId
            self.channel = channel
            self.accessTokenTimeToLive = accessTokenTimeToLive
            self.dynamicDescriptorsRequest = dynamicDescriptorsRequest
            self.merchantDetailsRequest = merchantDetailsRequest
            self.appleTtpMerchantId = appleTtpMerchantId
        }
    }
    
    // RESPONSE
    package struct AuthenticateResponse: Codable {
        package let gatewayResponse: GatewayResponse
        package let accessToken: String
        package let accessTokenTimeToLive: Int
        package let accessTokenType: String
    }
    
    // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    // CARD VERIFICATION RESPONSE (APPLE PROXIMITY READER)
    
    package struct CardVerificationResponse: Codable {
        package let cardReaderId: String
        package let transactionId: String
        package let generalCardData: String
        package let paymentCardData: String
    }
    
    // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    // ACCOUNT VERIFICATION REQUEST
    
    package struct AddressRequest: Codable {
        package let street: String
        package let houseNumberOrName: String
        package let city: String
        package let stateOrProvince: String
        package let postalCode: String
        package let country: String
        
        package init(street: String, houseNumberOrName: String, city: String, stateOrProvince: String, postalCode: String, country: String) {
            self.street = street
            self.houseNumberOrName = houseNumberOrName
            self.city = city
            self.stateOrProvince = stateOrProvince
            self.postalCode = postalCode
            self.country = country
        }
    }
        
    package struct BillingAddressRequest: Codable {
        package let firstName: String
        package let lastName: String
        package let address: AddressRequest?
        
        package init(firstName: String, lastName: String, addressRequest: AddressRequest? = nil) {
            
            self.firstName = firstName
            self.lastName = lastName
            self.address = addressRequest
        }
    }
    
    package struct PosFeaturesRequest: Codable {
        package let pinAuthenticationCapability: String
        package let terminalEntryCapability: String
        
        package init(pinAuthenticationCapability: String,
                    terminalEntryCapability: String) {
            
            self.pinAuthenticationCapability = pinAuthenticationCapability
            self.terminalEntryCapability = terminalEntryCapability
        }
    }
    
    package struct PosHardwareAndSoftwareRequest: Codable {
        package let softwareApplicationName: String
        package let softwareVersionNumber: String
        package let hardwareVendorIdentifier: String
        
        package init(softwareApplicationName: String,
                    softwareVersionNumber: String,
                    hardwareVendorIdentifier: String) {
            
            self.softwareApplicationName = softwareApplicationName
            self.softwareVersionNumber = softwareVersionNumber
            self.hardwareVendorIdentifier = hardwareVendorIdentifier
        }
    }
    
    package struct DataEntrySourceRequest: Codable {
        package let dataEntrySource: String
        package let posFeatures: PosFeaturesRequest
        package let posHardwareAndSoftware : PosHardwareAndSoftwareRequest?
        
        package init(dataEntrySource: String,
                    posFeatures: PosFeaturesRequest,
                    posHardwareAndSoftware: PosHardwareAndSoftwareRequest?) {
            
            self.dataEntrySource = dataEntrySource
            self.posFeatures = posFeatures
            self.posHardwareAndSoftware = posHardwareAndSoftware
        }
    }
    
    package struct TransactionInteractionRequest: Codable {
        package let origin: String
        package let posEntryMode: String
        package let posConditionCode: String
        package let additionalPosInformation: Models.DataEntrySourceRequest?
        
        package init(origin: String,
                    posEntryMode: String,
                    posConditionCode: String,
                    additionalPosInformation: Models.DataEntrySourceRequest?) {
            
            self.origin = origin
            self.posEntryMode = posEntryMode
            self.posConditionCode = posConditionCode
            self.additionalPosInformation = additionalPosInformation
        }
    }
    
    package struct AccountVerificationRequest: Codable {
        package let source: SourceRequest
        package let transactionDetails: TransactionDetailsRequest
        package let transactionInteraction: TransactionInteractionRequest
        package let billingAddress: BillingAddressRequest?
        package let merchantDetails: MerchantDetailsRequest
        
        package init(source: SourceRequest,
                    transactionDetails: TransactionDetailsRequest,
                    transactionInteraction: TransactionInteractionRequest,
                    billingAddress: BillingAddressRequest?,
                    merchantDetails: MerchantDetailsRequest) {
            self.source = source
            self.transactionDetails = transactionDetails
            self.transactionInteraction = transactionInteraction
            self.billingAddress = billingAddress
            self.merchantDetails = merchantDetails
        }
    }
    
    package struct AccountVerificationTokenRequest: Codable {
        package let source: Models.PaymentTokenSourceRequest
        package let transactionDetails: TransactionDetailsRequest
        package let transactionInteraction: TransactionInteractionRequest
        package let billingAddress: BillingAddressRequest?
        package let merchantDetails: MerchantDetailsRequest
        
        package init(source: Models.PaymentTokenSourceRequest,
                    transactionDetails: TransactionDetailsRequest,
                    transactionInteraction: TransactionInteractionRequest,
                    billingAddress: BillingAddressRequest?,
                    merchantDetails: MerchantDetailsRequest) {
            self.source = source
            self.transactionDetails = transactionDetails
            self.transactionInteraction = transactionInteraction
            self.billingAddress = billingAddress
            self.merchantDetails = merchantDetails
        }
    }
    
    // ACCOUNT VERIFICATION RESPONSE
    
    package struct MerchantDetailsResponse: Codable {
        package let tokenType: String?
        package let terminalId: String?
        package let merchantId: String?
    }
    
    package struct PosFeaturesResponse: Codable {
        package let pinAuthenticationCapability: String?
        package let PINcaptureCapability: String?
        package let terminalEntryCapability: String?
    }
    
    package struct AdditionalPosInformationResponse: Codable {
        package let dataEntrySource: String?
        package let stan: String?
        package let posFeatures: PosFeaturesResponse?
        package let cardPresentIndicator: String?
        package let cardPresentAtPosIndicator: String?
    }
    
    package struct TransactionInteractionResponse: Codable {
        package let posEntryMode: String?
        package let posConditionCode: String?
        package let posData: String?
        package let cardholderAuthenticationMethod: String?
        package let authorizationCharacteristicsIndicator: String?
        package let cardholderAuthenticationEntity: String?
        package let hostPosConditionCode: String?
        package let additionalPosInformation: AdditionalPosInformationResponse?
        package let cardPresentIndicator: String?
        package let cardPresentAtPosIndicator: String?
    }
    
    package struct TransactionDetailsResponse: Codable {
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
    
    package struct BillingAddressResponse: Codable {
        package let firstName: String?
        package let lastName: String?
    }
    
    package struct AvsCodeResponse: Codable {
        package let avsCode: String?
    }
    
    package struct AvsSecurityCodeResponse: Codable {
        package let streetMatch: String?
        package let postalCodeMatch: String?
        package let securityCodeMatch: String?
        package let association: AvsCodeResponse?
    }
    
    package struct BankAssociationDetailsResponse: Codable {
        package let associationResponseCode: String?
        package let avsSecurityCodeResponse: AvsSecurityCodeResponse?
    }
    
    package struct AdditionalInfoResponse: Codable {
        package let name: String?
        package let value: String?
    }

    package struct AccountVerificationResponse: Codable {
        package let gatewayResponse: GatewayResponse?
        package let processorResponseDetails: ProcessorResponseDetailsResponse?
        package let source: SourceResponse?
        package let billingAddress: BillingAddressResponse?
        package let transactionDetails: TransactionDetailsResponse?
        package let transactionInteraction: TransactionInteractionResponse?
        package let merchantDetails: MerchantDetailsResponse?
        package let paymentTokens: [PaymentTokenResponse]?
        
        package let error: ServerErrorResponse?
    }
    
    // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    // TOKENIZE REQUEST
    
    package struct TokenizeCardRequest: Codable {
        package let source: SourceRequest
        package let transactionDetails: TransactionDetailsRequest
        package let merchantDetails: MerchantDetailsRequest
        
        package init(source: SourceRequest,
                    transactionDetails: TransactionDetailsRequest,
                    merchantDetails: MerchantDetailsRequest) {
            
            self.source = source
            self.transactionDetails = transactionDetails
            self.merchantDetails = merchantDetails
        }
    }
    
    // TOKENIZE RESPONSE
    
    package struct PaymentTokenResponse: Codable {
        package let tokenData: String?
        package let tokenSource: String?
        package let tokenResponseCode: String?
        package let tokenResponseDescription: String?
    }
    
    package struct TokenizeCardResponse: Codable {
        package let gatewayResponse: GatewayResponse?
        package let source: SourceResponse?
        package let paymentTokens: [PaymentTokenResponse]?
        package let cardDetails: CardDetailsResponse?
        package let processorResponseDetails: ProcessorResponseDetailsResponse?
        package let error: ServerErrorResponse?
    }
    
    package struct AdditionalDataCommonProcessorRequest: Codable {
        package let processorName: String
        package let processingPlatform: String
        package let settlementPlatform: String
        package let priority: String
        
        package init(processorName: String,
                    processingPlatform: String,
                    settlementPlatform: String,
                    priority: String) {
            
            self.processorName = processorName
            self.processingPlatform = processingPlatform
            self.settlementPlatform = settlementPlatform
            self.priority = priority
        }
    }
    
    package struct AdditionalDataCommonProcessorsRequest: Codable {
        package let processors: AdditionalDataCommonProcessorRequest
        
        package init(processors: AdditionalDataCommonProcessorRequest) {
            self.processors = processors
        }
    }

    package struct AdditionalDataCommonRequest: Codable {
        package let origin: AdditionalDataCommonProcessorsRequest
        
        package init(origin: AdditionalDataCommonProcessorsRequest) {
            self.origin = origin
        }
    }
    
    package struct AmountRequest: Codable {
        package let total: Decimal
        package let currency: String
        
        package init(total: Decimal,
                    currency: String) {
            
            self.total = total
            self.currency = currency
        }
    }
    
    package struct PaymentTokenCardRequest: Codable {
        package let expirationMonth: String
        package let expirationYear: String
        
        package init(expirationMonth: String, expirationYear: String) {
            self.expirationMonth = expirationMonth
            self.expirationYear = expirationYear
        }
    }
    
    package struct PaymentTokenSourceRequest: Codable {
        package let sourceType: String
        package let tokenData:String
        package let tokenSource: String
        package let declineDuplicates: Bool
        package let card: PaymentTokenCardRequest
        
        package init(sourceType: String,
                    tokenData: String,
                    tokenSource: String,
                    declineDuplicates: Bool,
                    card: PaymentTokenCardRequest) {
            
            self.sourceType = sourceType
            self.tokenData = tokenData
            self.tokenSource = tokenSource
            self.declineDuplicates = declineDuplicates
            self.card = card
        }
    }
    
    package struct PaymentTokenChargeRequest: Codable {
        package let amount: Models.AmountRequest
        package let source: Models.PaymentTokenSourceRequest?
        package let transactionDetails: Models.TransactionDetailsRequest
        package let transactionInteraction: Models.TransactionInteractionRequest
        package let merchantDetails: Models.MerchantDetailsRequest
        
        package init(amount: Models.AmountRequest,
                    source: Models.PaymentTokenSourceRequest?,
                    transactionDetails: Models.TransactionDetailsRequest,
                    transactionInteraction: Models.TransactionInteractionRequest,
                    merchantDetails: Models.MerchantDetailsRequest) {
            
            self.amount = amount
            self.source = source
            self.transactionDetails = transactionDetails
            self.transactionInteraction = transactionInteraction
            self.merchantDetails = merchantDetails
        }
    }

    package struct ChargesRequest: Codable {
        package let amount: Models.AmountRequest
        package let source: Models.SourceRequest?
        package let merchantDetails: Models.MerchantDetailsRequest
        package let transactionDetails: Models.TransactionDetailsRequest
        package let referenceTransactionDetails: Models.ReferenceTransactionDetailsRequest?
        package let transactionInteraction: Models.TransactionInteractionRequest?
        package let additionalDataCommon: AdditionalDataCommonRequest?
        
        package init(amount: Models.AmountRequest,
                    source: Models.SourceRequest?,
                    merchantDetails: Models.MerchantDetailsRequest,
                    transactionDetails: Models.TransactionDetailsRequest,
                    referenceTransactionDetails: Models.ReferenceTransactionDetailsRequest?,
                    transactionInteraction: Models.TransactionInteractionRequest?,
                    additionalDataCommon: AdditionalDataCommonRequest?) {
            
            self.amount = amount
            self.source = source
            self.merchantDetails = merchantDetails
            self.transactionDetails = transactionDetails
            self.referenceTransactionDetails = referenceTransactionDetails
            self.transactionInteraction = transactionInteraction
            self.additionalDataCommon = additionalDataCommon
        }
    }
    
    package struct CommerceHubResponse: Codable {
        package let gatewayResponse: GatewayResponse?
        package let source: SourceResponse?
        package let paymentReceipt: PaymentReceiptResponse?
        package let transactionDetails: TransactionDetailsResponse?
        package let transactionInteraction: TransactionInteractionResponse?
        package let merchantDetails: MerchantDetailsResponse?
        package let networkDetails: NetworkDetailsResponse?
        package let cardDetails: CardDetailsResponse?
        package let paymentTokens: [PaymentTokenResponse]?
        package let error: ServerErrorResponse?
    }

    package struct CancelsRequest: Codable {
        package let amount: Models.AmountRequest
        package let merchantDetails: Models.MerchantDetailsRequest
        package let referenceTransactionDetails: Models.ReferenceTransactionDetailsRequest
        
        package init(amount: Models.AmountRequest,
                    merchantDetails: Models.MerchantDetailsRequest,
                    referenceTransactionDetails: Models.ReferenceTransactionDetailsRequest) {
            
            self.amount = amount
            self.merchantDetails = merchantDetails
            self.referenceTransactionDetails = referenceTransactionDetails
        }
    }
    
    package struct RefundsRequest: Codable {
        package let amount: Models.AmountRequest
        package let source: Models.SourceRequest?
        package let merchantDetails: Models.MerchantDetailsRequest
        package let transactionDetails: Models.TransactionDetailsRequest?
        package let referenceTransactionDetails: Models.ReferenceTransactionDetailsRequest?
        package let transactionInteraction: Models.TransactionInteractionRequest?
        package let additionalDataCommon: AdditionalDataCommonRequest?
        
        package init(amount: Models.AmountRequest,
                    source: Models.SourceRequest?,
                    merchantDetails: Models.MerchantDetailsRequest,
                    transactionDetails: Models.TransactionDetailsRequest?,
                    referenceTransactionDetails: Models.ReferenceTransactionDetailsRequest?,
                    transactionInteraction: Models.TransactionInteractionRequest?,
                    additionalDataCommon: AdditionalDataCommonRequest?) {
            
            self.amount = amount
            self.source = source
            self.merchantDetails = merchantDetails
            self.transactionDetails = transactionDetails
            self.referenceTransactionDetails = referenceTransactionDetails
            self.transactionInteraction = transactionInteraction
            self.additionalDataCommon = additionalDataCommon
        }
    }
    
    package struct ApprovedAmountResponse: Codable {
        package let total: Decimal?
        package let currency: String?
    }
    
    package struct ProcessorResponseIndicatorsResponse: Codable {
        package let alternateRouteDebitIndicator: Bool?
        package let signatureLineIndicator: Bool?
        package let signatureDebitRouteIndicator: Bool?
    }
    
    package struct ProcessorResponseDetailsResponse: Codable {
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
        package let responseIndicators: ProcessorResponseIndicatorsResponse?
        package let bankAssociationDetails: BankAssociationDetailsResponse?
        package let additionalInfo: [AdditionalInfoResponse]?
    }
    
    package struct PaymentReceiptResponse: Codable {
        package let approvedAmount: ApprovedAmountResponse?
        package let processorResponseDetails: ProcessorResponseDetailsResponse?
    }
    
    // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    // TRANSACTION INQUIRY REQUEST
    package struct TransactionInquiryRequest: Codable {
        package let referenceTransactionDetails: ReferenceTransactionDetailsRequest
        package let merchantDetails: MerchantDetailsRequest
        
        package init(referenceTransactionDetails: ReferenceTransactionDetailsRequest,
                    merchantDetails: MerchantDetailsRequest) {
            
            self.referenceTransactionDetails = referenceTransactionDetails
            self.merchantDetails = merchantDetails
        }
    }
    
    // - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - - -
    // INQUIRY RESPONSE
    
    package struct ErrorResponse: Codable {
        package let type: String?
        package let field: String?
        package let code: String?
        package let message: String?
    }
    
    package struct ServerErrorResponse: Codable {
        package let gatewayResponse: GatewayErrorResponse
        package let error: [ErrorResponse]?
    }

    package struct GatewayErrorResponse: Codable {
        package let transactionType: String?
        package let transactionState: String?
        package let transactionProcessingDetails: TransactionProcessingDetailsResponse?
    }

    package struct DebitPinlessIndicatorResponse: Codable {
        package let debitNetworkId: String?
        package let pinnedPOS: String?
    }
    
    package struct CardDetailsResponse: Codable {
        package let binSource: String?
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
        package let debitPinlessIndicator: [DebitPinlessIndicatorResponse]?
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
    
    package struct NetworkResponse: Codable {
        package let network: String?
        package let cardAuthenticationResultCode: String?
    }
    
    package struct NetworkDetailsResponse: Codable {
        package let network: NetworkResponse?
        package let debitNetworkId: String?
        package let networkResponseCode: String?
        package let cardLevelResultCode: String?
        package let validationCode: String?
        package let transactionIdentifier: String?
    }
    
    package struct InquireResponse: Codable {
        package let gatewayResponse: GatewayResponse?
        package let source: SourceResponse?
        package let paymentReceipt: PaymentReceiptResponse?
        package let transactionDetails: TransactionDetailsResponse?
        package let transactionInteraction: TransactionInteractionResponse?
        package let merchantDetails: MerchantDetailsResponse?
        package let networkDetails: NetworkDetailsResponse?
        package let cardDetails: CardDetailsResponse?
        package let paymentTokens: [PaymentTokenResponse]?
        package let error: ServerErrorResponse?
    }
}

extension Models.ApprovedAmountResponse {

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


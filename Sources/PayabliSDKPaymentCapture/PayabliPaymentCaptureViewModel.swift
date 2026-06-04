import Foundation
import PayabliSDKCore
import PayabliSDKPaymentMethod
import SwiftUI

@MainActor
final class PayabliPaymentCaptureViewModel: ObservableObject {
    @Published var selectedMethod: PayabliPaymentMethodType
    @Published private var cardholderNameStorage = ""
    @Published private var cardNumberStorage = ""
    @Published var cardExpiration = ""
    @Published var cardExpirationMonth: Int?
    @Published var cardExpirationYear: Int?
    @Published private var cardCvvStorage = ""
    @Published private var cardZipStorage = ""
    @Published private var achHolderStorage = ""
    @Published private var achRoutingStorage = ""
    @Published private var achAccountStorage = ""
    @Published var achAccountType: PayabliACHAccountType = .checking
    @Published var achHolderType: PayabliACHHolderType = .personal
    @Published var achSecCode: PayabliACHSecCode = .web
    @Published var achDevice = ""
    @Published var methodDescription = ""
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var customerNumber = ""
    @Published var billingEmail = ""
    @Published private var billingZipStorage = ""
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?

    private let component: PayabliPaymentCapture
    private let configuration: PayabliPaymentCaptureFormConfiguration

    init(
        component: PayabliPaymentCapture,
        configuration: PayabliPaymentCaptureFormConfiguration = PayabliPaymentCaptureFormConfiguration()
    ) {
        self.component = component
        self.configuration = configuration
        self.selectedMethod = configuration.defaultMethod
    }

    var cardholderName: String {
        get { cardholderNameStorage }
        set { cardholderNameStorage = limitCardholderName(newValue) }
    }

    var cardNumber: String {
        get { cardNumberStorage }
        set { cardNumberStorage = formatCardNumber(newValue) }
    }

    var cardCvv: String {
        get { cardCvvStorage }
        set { cardCvvStorage = limitCardCvv(newValue) }
    }

    var cardZip: String {
        get { cardZipStorage }
        set { cardZipStorage = limitPostalCode(newValue) }
    }

    var achHolder: String {
        get { achHolderStorage }
        set { achHolderStorage = limitACHHolderName(newValue) }
    }

    var achRouting: String {
        get { achRoutingStorage }
        set { achRoutingStorage = limitACHRouting(newValue) }
    }

    var achAccount: String {
        get { achAccountStorage }
        set { achAccountStorage = limitACHAccount(newValue) }
    }

    var billingZip: String {
        get { billingZipStorage }
        set { billingZipStorage = limitPostalCode(newValue) }
    }

    var activeFields: [PayabliPaymentCaptureField] {
        switch selectedMethod {
        case .card:
            return configuration.cardFieldOrder
        case .ach:
            return configuration.achFieldOrder
        }
    }

    var detectedCardBrand: PayabliPaymentMethodCardBrand {
        PayabliPaymentMethodCardBrand.detect(cardNumber: cardNumber)
    }

    var cardNumberValidationMessage: String? {
        let digits = cardNumber.payabliCaptureDigitsOnly
        guard validation.requiresLuhnCheck,
              digits.count >= PayabliPaymentCaptureInputLimits.minimumCardNumberDigits,
              !Self.passesLuhn(digits)
        else {
            return nil
        }

        return "Invalid Card Number"
    }

    var expirationDisplayText: String {
        switch (selectedExpirationMonth, selectedExpirationYear) {
        case let (.some(month), .some(year)):
            return String(format: "%02d/%02d", month, year % 100)
        case let (.some(month), .none):
            return String(format: "%02d/YY", month)
        case let (.none, .some(year)):
            return String(format: "MM/%02d", year % 100)
        case (.none, .none):
            return "MM/YY"
        }
    }

    var hasSelectedExpiration: Bool {
        selectedExpirationMonth != nil || selectedExpirationYear != nil
    }

    var canSubmit: Bool {
        guard component.requestConfiguration != nil else { return false }

        switch selectedMethod {
        case .card:
            return fieldHasRequiredValue(.cardholderName)
                && fieldHasRequiredValue(.cardNumber)
                && cardNumberValidationMessage == nil
                && cardExpiration.payabliCaptureDigitsOnly.count >= 4
                && fieldHasRequiredValue(.cardCvv)
                && fieldHasRequiredValue(.cardZip)
                && paymentDetailsAreValid
                && requiredFieldsAreSatisfied
        case .ach:
            return component.operation == .capture
                && fieldHasRequiredValue(.achHolder)
                && fieldHasRequiredValue(.achRouting)
                && fieldHasRequiredValue(.achAccount)
                && paymentDetailsAreValid
                && requiredFieldsAreSatisfied
        }
    }

    func submit() async throws -> PayabliPaymentCaptureResult {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            guard let requestConfiguration = component.requestConfiguration else {
                throw PayabliPaymentCaptureError.invalidInput("Payment capture request configuration is required.")
            }
            try validateRequiredFields()
            let request = requestConfiguration.request(
                paymentMethod: paymentMethod(),
                customerData: mergedCustomerData(),
                orderDescription: mergedOrderDescription()
            )
            let result = try await component.submitConfigured(request)
            clearSensitiveFields()
            return result
        } catch {
            clearSensitiveFieldsAfterFailure()
            errorMessage = Self.message(for: error)
            throw error
        }
    }

    func formatCardNumber(_ value: String) -> String {
        let digits = String(value.payabliCaptureDigitsOnly.prefix(PayabliPaymentCaptureInputLimits.maximumCardNumberDigits))
        guard configuration.formatting.insertsCardNumberSpaces else { return digits }

        var groups: [String] = []
        var current = digits.startIndex
        while current < digits.endIndex {
            let next = digits.index(current, offsetBy: 4, limitedBy: digits.endIndex) ?? digits.endIndex
            groups.append(String(digits[current ..< next]))
            current = next
        }
        return groups.joined(separator: " ")
    }

    func limitCardholderName(_ value: String) -> String {
        String(value.prefix(PayabliPaymentCaptureInputLimits.maximumCardholderNameCharacters))
    }

    func limitCardCvv(_ value: String) -> String {
        String(value.payabliCaptureDigitsOnly.prefix(PayabliPaymentCaptureInputLimits.maximumCardCvvDigits))
    }

    func limitPostalCode(_ value: String) -> String {
        String(value.prefix(PayabliPaymentCaptureInputLimits.maximumPostalCodeCharacters))
    }

    func limitACHHolderName(_ value: String) -> String {
        String(value.prefix(PayabliPaymentCaptureInputLimits.maximumACHHolderNameCharacters))
    }

    func limitACHRouting(_ value: String) -> String {
        String(value.payabliCaptureDigitsOnly.prefix(PayabliPaymentCaptureInputLimits.achRoutingDigits))
    }

    func limitACHAccount(_ value: String) -> String {
        String(value.payabliCaptureDigitsOnly.prefix(PayabliPaymentCaptureInputLimits.maximumACHAccountDigits))
    }

    func formatExpiration(_ value: String) -> String {
        let digits = String(value.payabliCaptureDigitsOnly.prefix(4))
        guard digits.count > 2 else { return digits }
        let month = digits.prefix(2)
        let year = digits.dropFirst(2)
        return "\(month)\(configuration.formatting.expirationSeparator)\(year)"
    }

    func selectExpirationMonth(_ month: Int) {
        cardExpirationMonth = min(max(month, 1), 12)
        synchronizeExpirationText()
    }

    func selectExpirationYear(_ year: Int) {
        cardExpirationYear = year
        synchronizeExpirationText()
    }

    func ensureExpirationSelection(defaultDate: Date = Date()) {
        let calendar = Calendar.current
        if cardExpirationMonth == nil {
            cardExpirationMonth = selectedExpirationMonth ?? calendar.component(.month, from: defaultDate)
        }
        if cardExpirationYear == nil {
            cardExpirationYear = selectedExpirationYear ?? calendar.component(.year, from: defaultDate)
        }
        synchronizeExpirationText()
    }

    func paymentSummaryLabelText(for field: PayabliPaymentCaptureField) -> String {
        configuration.paymentSummary.labelText(
            for: field,
            labels: configuration.labels
        )
    }

    func paymentSummaryValueText(for field: PayabliPaymentCaptureField) -> String {
        configuration.paymentSummary.valueText(
            for: field,
            paymentDetails: component.requestConfiguration?.paymentDetails
        )
    }

    func paymentSummaryAccessibilityText(for field: PayabliPaymentCaptureField) -> String {
        configuration.paymentSummary.accessibilityText(
            for: field,
            labels: configuration.labels,
            paymentDetails: component.requestConfiguration?.paymentDetails
        )
    }

    private var validation: PayabliPaymentMethodValidation {
        component.requestConfiguration?.validation ?? .default
    }

    private func paymentMethod() -> PayabliPaymentCapturePaymentMethod {
        switch selectedMethod {
        case .card:
            return .card(PayabliPaymentCaptureCardMethod(
                data: PayabliCardPaymentMethodData(
                    cardNumber: cardNumber,
                    expiration: cardExpiration,
                    cardholderName: cardholderName,
                    cvv: cardCvv,
                    billingZip: cardZip
                )
            ))
        case .ach:
            return .ach(PayabliPaymentCaptureACHMethod(
                data: PayabliACHPaymentMethodData(
                    accountNumber: achAccount,
                    accountType: achAccountType,
                    holderName: achHolder,
                    routingNumber: achRouting,
                    secCode: configuration.hiddenValues.achSecCode ?? .web,
                    holderType: fieldIsVisible(.achHolderType) ? achHolderType : configuration.hiddenValues.achHolderType,
                    device: fieldIsVisible(.achDevice) ? achDevice : configuration.hiddenValues.achDevice
                )
            ))
        }
    }

    private func mergedCustomerData() -> PayabliPaymentMethodCustomerData? {
        var customer = component.requestConfiguration?.customerData
            ?? configuration.options.customerData
            ?? PayabliPaymentMethodCustomerData()
        customer.payabliCaptureMerge(configuration.hiddenValues.customerData)
        customer.payabliCaptureApply(\.firstName, firstName.payabliCaptureTrimmed.payabliCaptureNilIfEmpty)
        customer.payabliCaptureApply(\.lastName, lastName.payabliCaptureTrimmed.payabliCaptureNilIfEmpty)
        customer.payabliCaptureApply(\.customerNumber, customerNumber.payabliCaptureTrimmed.payabliCaptureNilIfEmpty)
        customer.payabliCaptureApply(\.billingEmail, billingEmail.payabliCaptureTrimmed.payabliCaptureNilIfEmpty)
        customer.payabliCaptureApply(\.billingZip, billingZip.payabliCaptureTrimmed.payabliCaptureNilIfEmpty)
        return customer.payabliCaptureHasAnyValue ? customer : nil
    }

    private func mergedOrderDescription() -> String? {
        methodDescription.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
            ?? configuration.hiddenValues.methodDescription?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
    }

    private func fieldIsVisible(_ field: PayabliPaymentCaptureField) -> Bool {
        activeFields.contains(field)
    }

    private var requiredFieldsAreSatisfied: Bool {
        activeRequiredFields.allSatisfy(fieldHasRequiredValue)
    }

    private var paymentDetailsAreValid: Bool {
        guard let paymentDetails = component.requestConfiguration?.paymentDetails else { return false }
        return paymentDetails.totalAmount > 0 && (paymentDetails.serviceFee ?? 0) >= 0
    }

    private func validateRequiredFields() throws {
        for field in activeRequiredFields {
            guard fieldHasRequiredValue(field) else {
                throw PayabliPaymentCaptureError.invalidInput("\(configuration.labels.label(for: field)) is required.")
            }
        }
    }

    private var activeRequiredFields: [PayabliPaymentCaptureField] {
        activeFields.filter { configuration.requiredFields.contains($0) }
    }

    private func fieldHasRequiredValue(_ field: PayabliPaymentCaptureField) -> Bool {
        switch field {
        case .cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip:
            return cardFieldHasRequiredValue(field)
        case .achHolder, .achRouting, .achAccount, .achAccountType, .achHolderType, .achSecCode, .achDevice:
            return achFieldHasRequiredValue(field)
        case .methodDescription, .firstName, .lastName, .customerNumber, .billingEmail, .billingZip:
            return customerFieldHasRequiredValue(field)
        case .amount, .serviceFee:
            return paymentFieldHasRequiredValue(field)
        }
    }

    private func cardFieldHasRequiredValue(_ field: PayabliPaymentCaptureField) -> Bool {
        switch field {
        case .cardholderName:
            return !cardholderName.payabliCaptureTrimmed.isEmpty
        case .cardNumber:
            return (PayabliPaymentCaptureInputLimits.minimumCardNumberDigits ... PayabliPaymentCaptureInputLimits.maximumCardNumberDigits)
                .contains(cardNumber.payabliCaptureDigitsOnly.count)
                && cardNumberValidationMessage == nil
        case .cardExpiration:
            return cardExpiration.payabliCaptureDigitsOnly.count >= 4
        case .cardCvv:
            return (PayabliPaymentCaptureInputLimits.minimumCardCvvDigits ... PayabliPaymentCaptureInputLimits.maximumCardCvvDigits)
                .contains(cardCvv.payabliCaptureDigitsOnly.count)
        case .cardZip:
            return !cardZip.payabliCaptureTrimmed.isEmpty
        default:
            return true
        }
    }

    private func achFieldHasRequiredValue(_ field: PayabliPaymentCaptureField) -> Bool {
        switch field {
        case .achHolder:
            return !achHolder.payabliCaptureTrimmed.isEmpty
        case .achRouting:
            return achRouting.payabliCaptureDigitsOnly.count == PayabliPaymentCaptureInputLimits.achRoutingDigits
        case .achAccount:
            return (PayabliPaymentCaptureInputLimits.minimumACHAccountDigits ... PayabliPaymentCaptureInputLimits.maximumACHAccountDigits)
                .contains(achAccount.payabliCaptureDigitsOnly.count)
        case .achAccountType:
            return true
        case .achHolderType:
            return fieldIsVisible(.achHolderType) || configuration.hiddenValues.achHolderType != nil
        case .achSecCode:
            return true
        case .achDevice:
            return !achDevice.payabliCaptureTrimmed.isEmpty || configuration.hiddenValues.achDevice?.payabliCaptureTrimmed
                .payabliCaptureNilIfEmpty != nil
        default:
            return true
        }
    }

    private func customerFieldHasRequiredValue(_ field: PayabliPaymentCaptureField) -> Bool {
        switch field {
        case .methodDescription:
            return !methodDescription.payabliCaptureTrimmed.isEmpty || configuration.hiddenValues.methodDescription?.payabliCaptureTrimmed
                .payabliCaptureNilIfEmpty != nil
        case .firstName:
            return !firstName.payabliCaptureTrimmed.isEmpty
        case .lastName:
            return !lastName.payabliCaptureTrimmed.isEmpty
        case .customerNumber:
            return !customerNumber.payabliCaptureTrimmed.isEmpty
        case .billingEmail:
            return !billingEmail.payabliCaptureTrimmed.isEmpty
        case .billingZip:
            return !billingZip.payabliCaptureTrimmed.isEmpty
        default:
            return true
        }
    }

    private func paymentFieldHasRequiredValue(_ field: PayabliPaymentCaptureField) -> Bool {
        switch field {
        case .amount:
            return component.requestConfiguration?.paymentDetails.totalAmount ?? 0 > 0
        case .serviceFee:
            return component.requestConfiguration?.paymentDetails.serviceFee.map { $0 >= 0 } ?? true
        default:
            return true
        }
    }

    private var selectedExpirationMonth: Int? {
        if let cardExpirationMonth {
            return cardExpirationMonth
        }
        let digits = cardExpiration.payabliCaptureDigitsOnly
        guard digits.count >= 2 else { return nil }
        let monthText = String(digits.prefix(2))
        guard let month = Int(monthText), (1 ... 12).contains(month) else { return nil }
        return month
    }

    private var selectedExpirationYear: Int? {
        if let cardExpirationYear {
            return cardExpirationYear
        }
        let digits = cardExpiration.payabliCaptureDigitsOnly
        guard digits.count >= 4 else { return nil }
        let yearSuffix = String(digits.suffix(2))
        guard let year = Int(yearSuffix) else { return nil }
        return 2000 + year
    }

    private func synchronizeExpirationText() {
        guard let month = cardExpirationMonth, let year = cardExpirationYear else { return }
        cardExpiration = String(format: "%02d%@%02d", month, configuration.formatting.expirationSeparator, year % 100)
    }

    private func clearSensitiveFields() {
        cardNumberStorage = ""
        cardExpiration = ""
        cardExpirationMonth = nil
        cardExpirationYear = nil
        cardCvvStorage = ""
        achRoutingStorage = ""
        achAccountStorage = ""
    }

    private func clearSensitiveFieldsAfterFailure() {
        cardCvvStorage = ""
        achAccountStorage = ""
    }

    private static func message(for error: Error) -> String {
        if let payabliError = error as? any PayabliError {
            if let detail = payabliError.detail?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty, detail != payabliError.reason {
                return "\(payabliError.reason)\n\(detail)"
            }
            return payabliError.reason
        }
        return String(describing: error)
    }

    private static func passesLuhn(_ digits: String) -> Bool {
        var sum = 0
        var shouldDouble = false
        for character in digits.reversed() {
            guard var value = Int(String(character)) else { return false }
            if shouldDouble {
                value *= 2
                if value > 9 {
                    value -= 9
                }
            }
            sum += value
            shouldDouble.toggle()
        }
        return sum % 10 == 0
    }
}

private enum PayabliPaymentCaptureInputLimits {
    static let minimumCardNumberDigits = 12
    static let maximumCardNumberDigits = 19
    static let minimumCardCvvDigits = 3
    static let maximumCardCvvDigits = 4
    static let maximumPostalCodeCharacters = 12
    static let maximumCardholderNameCharacters = 60
    static let maximumACHHolderNameCharacters = 60
    static let achRoutingDigits = 9
    static let minimumACHAccountDigits = 4
    static let maximumACHAccountDigits = 17
}

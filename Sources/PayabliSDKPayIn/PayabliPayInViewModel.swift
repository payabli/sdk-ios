import Foundation
import PayabliSDKCore
import SwiftUI

@MainActor
final class PayabliPayInViewModel: ObservableObject {
    @Published var selectedMethod: PayabliPayInMethodType
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
    @Published var accountType: PayabliPayInAccountType = .checking
    @Published var accountHolderType: PayabliPayInAccountHolderType = .personal
    @Published var secCode: PayabliPayInSecCode = .web
    @Published var deviceId = ""
    @Published var methodDescription = ""
    @Published var firstName = ""
    @Published var lastName = ""
    @Published var customerNumber = ""
    @Published var billingEmail = ""
    @Published private var billingZipStorage = ""
    @Published private(set) var isSubmitting = false
    @Published private(set) var errorMessage: String?

    private(set) var component: PayabliPayIn
    private var configuration: PayabliPayInFormConfiguration
    private var lifecycleSignature: String

    init(
        component: PayabliPayIn,
        configuration: PayabliPayInFormConfiguration = PayabliPayInFormConfiguration()
    ) {
        self.component = component
        self.configuration = configuration
        lifecycleSignature = Self.lifecycleSignature(
            component: component,
            configuration: configuration
        )
        let availableMethods = Self.availableMethods(
            operation: component.operation,
            configuredMethods: configuration.allowedMethods
        )
        self.selectedMethod = availableMethods.contains(configuration.defaultMethod)
            ? configuration.defaultMethod
            : availableMethods[0]
    }

    func update(
        component: PayabliPayIn,
        configuration: PayabliPayInFormConfiguration
    ) {
        let nextSignature = Self.lifecycleSignature(
            component: component,
            configuration: configuration
        )
        guard nextSignature != lifecycleSignature else { return }

        objectWillChange.send()
        self.component = component
        self.configuration = configuration
        lifecycleSignature = nextSignature

        let methods = availableMethods
        if !methods.contains(selectedMethod) {
            selectedMethod = methods.contains(configuration.defaultMethod)
                ? configuration.defaultMethod
                : methods[0]
        }
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

    var accountHolder: String {
        get { achHolderStorage }
        set { achHolderStorage = limitAccountHolderName(newValue) }
    }

    var routingNumber: String {
        get { achRoutingStorage }
        set { achRoutingStorage = limitRoutingNumber(newValue) }
    }

    var accountNumber: String {
        get { achAccountStorage }
        set { achAccountStorage = limitAccountNumber(newValue) }
    }

    var billingZip: String {
        get { billingZipStorage }
        set { billingZipStorage = limitPostalCode(newValue) }
    }

    var activeFields: [PayabliPayInField] {
        let fields = switch effectiveSelectedMethod {
        case .card:
            configuration.cardFieldOrder
        case .bankAccount:
            configuration.bankFieldOrder
        }

        guard component.operation == .storePaymentMethod else { return fields }
        return fields.filter { field in
            field != .amount && field != .serviceFee
        }
    }

    var detectedCardBrand: PayabliPayInCardBrand {
        PayabliPayInCardBrand.detect(cardNumber: cardNumber)
    }

    var availableMethods: [PayabliPayInMethodType] {
        Self.availableMethods(
            operation: component.operation,
            configuredMethods: configuration.allowedMethods
        )
    }

    var effectiveSelectedMethod: PayabliPayInMethodType {
        availableMethods.contains(selectedMethod) ? selectedMethod : availableMethods[0]
    }

    func normalizeSelectedMethodForAvailableMethods() {
        guard !availableMethods.contains(selectedMethod) else { return }
        selectedMethod = availableMethods[0]
    }

    var cardNumberValidationMessage: String? {
        let digits = cardNumber.payabliCaptureDigitsOnly
        guard validation.requiresLuhnCheck,
              digits.count >= PayabliPayInInputLimits.minimumCardNumberDigits,
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
        switch effectiveSelectedMethod {
        case .card:
            return fieldHasRequiredValue(.cardholderName)
                && fieldHasRequiredValue(.cardNumber)
                && cardNumberValidationMessage == nil
                && cardExpiration.payabliCaptureDigitsOnly.count >= 4
                && fieldHasRequiredValue(.cardCvv)
                && fieldHasRequiredValue(.cardZip)
                && operationConfigurationIsValid
                && requiredFieldsAreSatisfied
        case .bankAccount:
            return fieldHasRequiredValue(.accountHolder)
                && fieldHasRequiredValue(.routingNumber)
                && fieldHasRequiredValue(.accountNumber)
                && operationConfigurationIsValid
                && requiredFieldsAreSatisfied
        }
    }

    func submit() async throws -> PayabliPayInResult {
        errorMessage = nil
        guard !isSubmitting else {
            let error = PayabliPayInError.submissionInProgress
            errorMessage = Self.message(for: error)
            throw error
        }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            try validateRequiredFields()
            let result: PayabliPayInResult
            switch component.operation {
            case .storePaymentMethod:
                result = try await component.submitConfigured(
                    methodInput(),
                    options: mergedTokenStorageOptions()
                )
            case .capture, .authorize:
                guard let requestConfiguration = component.requestConfiguration else {
                    throw PayabliPayInError.invalidInput("Payment request configuration is required.")
                }
                let request = requestConfiguration.request(
                    paymentMethod: paymentMethod(),
                    customerData: mergedCustomerData(),
                    orderDescription: mergedOrderDescription()
                )
                result = try await component.submitConfigured(request)
            }
            clearSensitiveFields()
            return result
        } catch {
            clearSensitiveFieldsAfterFailure()
            errorMessage = Self.message(for: error)
            throw error
        }
    }

    func formatCardNumber(_ value: String) -> String {
        let digits = String(value.payabliCaptureDigitsOnly.prefix(PayabliPayInInputLimits.maximumCardNumberDigits))
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
        String(value.prefix(PayabliPayInInputLimits.maximumCardholderNameCharacters))
    }

    func limitCardCvv(_ value: String) -> String {
        String(value.payabliCaptureDigitsOnly.prefix(PayabliPayInInputLimits.maximumCardCvvDigits))
    }

    func limitPostalCode(_ value: String) -> String {
        String(value.prefix(PayabliPayInInputLimits.maximumPostalCodeCharacters))
    }

    func limitAccountHolderName(_ value: String) -> String {
        String(value.prefix(PayabliPayInInputLimits.maximumAccountHolderNameCharacters))
    }

    func limitRoutingNumber(_ value: String) -> String {
        String(value.payabliCaptureDigitsOnly.prefix(PayabliPayInInputLimits.routingNumberDigits))
    }

    func limitAccountNumber(_ value: String) -> String {
        String(value.payabliCaptureDigitsOnly.prefix(PayabliPayInInputLimits.maximumAccountNumberDigits))
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

    func paymentSummaryLabelText(for field: PayabliPayInField) -> String {
        configuration.paymentSummary.labelText(
            for: field,
            labels: configuration.labels
        )
    }

    func paymentSummaryValueText(for field: PayabliPayInField) -> String {
        configuration.paymentSummary.valueText(
            for: field,
            paymentDetails: component.requestConfiguration?.paymentDetails
        )
    }

    func paymentSummaryAccessibilityText(for field: PayabliPayInField) -> String {
        configuration.paymentSummary.accessibilityText(
            for: field,
            labels: configuration.labels,
            paymentDetails: component.requestConfiguration?.paymentDetails
        )
    }

    private var validation: PayabliPayInValidation {
        component.requestConfiguration?.validation ?? configuration.options.validation
    }

    private static func availableMethods(
        operation: PayabliPayInOperation,
        configuredMethods: [PayabliPayInMethodType]
    ) -> [PayabliPayInMethodType] {
        let methods = configuredMethods.filter { method in
            switch operation {
            case .storePaymentMethod, .capture:
                return true
            case .authorize:
                return method.authorizationMethod != nil
            }
        }
        return methods.isEmpty ? [.card] : methods
    }

    private static func lifecycleSignature(
        component: PayabliPayIn,
        configuration: PayabliPayInFormConfiguration
    ) -> String {
        [
            "component:\(ObjectIdentifier(component))",
            "operation:\(component.operation.rawValue)",
            "request:\(component.requestConfiguration?.payabliViewModelSignature ?? "")",
            "configuration:\(configuration.payabliViewModelSignature)"
        ]
        .joined(separator: "|")
    }

    private func methodInput() -> PayabliPayInMethodInput {
        switch effectiveSelectedMethod {
        case .card:
            return .card(PayabliPayInCardData(
                cardNumber: cardNumber,
                expiration: cardExpiration,
                cardholderName: cardholderName,
                cvv: cardCvv,
                billingZip: cardZip
            ))
        case .bankAccount:
            return .bankAccount(PayabliPayInBankAccountData(
                accountNumber: accountNumber,
                accountType: accountType,
                holderName: accountHolder,
                routingNumber: routingNumber,
                secCode: configuration.hiddenValues.secCode ?? .web,
                holderType: fieldIsVisible(.accountHolderType) ? accountHolderType : configuration.hiddenValues.accountHolderType,
                device: fieldIsVisible(.deviceId) ? deviceId : configuration.hiddenValues.deviceId
            ))
        }
    }

    private func paymentMethod() -> PayabliPayInPaymentMethod {
        switch effectiveSelectedMethod {
        case .card:
            return .card(PayabliPayInPaymentMethod.Card(
                data: PayabliPayInCardData(
                    cardNumber: cardNumber,
                    expiration: cardExpiration,
                    cardholderName: cardholderName,
                    cvv: cardCvv,
                    billingZip: cardZip
                )
            ))
        case .bankAccount:
            return .bankAccount(PayabliPayInPaymentMethod.BankAccount(
                data: PayabliPayInBankAccountData(
                    accountNumber: accountNumber,
                    accountType: accountType,
                    holderName: accountHolder,
                    routingNumber: routingNumber,
                    secCode: configuration.hiddenValues.secCode ?? .web,
                    holderType: fieldIsVisible(.accountHolderType) ? accountHolderType : configuration.hiddenValues.accountHolderType,
                    device: fieldIsVisible(.deviceId) ? deviceId : configuration.hiddenValues.deviceId
                )
            ))
        }
    }

    private func mergedCustomerData() -> PayabliPayInCustomerData? {
        var customer = component.requestConfiguration?.customerData
            ?? configuration.options.customerData
            ?? PayabliPayInCustomerData()
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

    private func mergedTokenStorageOptions() -> PayabliPayInTokenStorageOptions {
        var options = configuration.options
        options.customerData = mergedCustomerData()
        options.methodDescription = mergedOrderDescription()
        return options
    }

    private func fieldIsVisible(_ field: PayabliPayInField) -> Bool {
        activeFields.contains(field)
    }

    private var requiredFieldsAreSatisfied: Bool {
        activeRequiredFields.allSatisfy(fieldHasRequiredValue)
    }

    private var operationConfigurationIsValid: Bool {
        if component.operation == .storePaymentMethod {
            return true
        }
        return paymentDetailsAreValid
    }

    private var paymentDetailsAreValid: Bool {
        guard let paymentDetails = component.requestConfiguration?.paymentDetails else { return false }
        return paymentDetails.totalAmount > 0 && (paymentDetails.serviceFee ?? 0) >= 0
    }

    private func validateRequiredFields() throws {
        for field in activeRequiredFields {
            guard fieldHasRequiredValue(field) else {
                throw PayabliPayInError.invalidInput("\(configuration.labels.label(for: field)) is required.")
            }
        }
    }

    private var activeRequiredFields: [PayabliPayInField] {
        activeFields.filter { configuration.requiredFields.contains($0) }
    }

    private func fieldHasRequiredValue(_ field: PayabliPayInField) -> Bool {
        switch field {
        case .cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip:
            return cardFieldHasRequiredValue(field)
        case .accountHolder, .routingNumber, .accountNumber, .accountType, .accountHolderType, .secCode, .deviceId:
            return achFieldHasRequiredValue(field)
        case .methodDescription, .firstName, .lastName, .customerNumber, .billingEmail, .billingZip:
            return customerFieldHasRequiredValue(field)
        case .amount, .serviceFee:
            return paymentFieldHasRequiredValue(field)
        }
    }

    private func cardFieldHasRequiredValue(_ field: PayabliPayInField) -> Bool {
        switch field {
        case .cardholderName:
            return !cardholderName.payabliCaptureTrimmed.isEmpty
        case .cardNumber:
            return (PayabliPayInInputLimits.minimumCardNumberDigits ... PayabliPayInInputLimits
                .maximumCardNumberDigits)
                .contains(cardNumber.payabliCaptureDigitsOnly.count)
                && cardNumberValidationMessage == nil
        case .cardExpiration:
            return cardExpiration.payabliCaptureDigitsOnly.count >= 4
        case .cardCvv:
            return (PayabliPayInInputLimits.minimumCardCvvDigits ... PayabliPayInInputLimits.maximumCardCvvDigits)
                .contains(cardCvv.payabliCaptureDigitsOnly.count)
        case .cardZip:
            return !cardZip.payabliCaptureTrimmed.isEmpty
        default:
            return true
        }
    }

    private func achFieldHasRequiredValue(_ field: PayabliPayInField) -> Bool {
        switch field {
        case .accountHolder:
            return !accountHolder.payabliCaptureTrimmed.isEmpty
        case .routingNumber:
            return routingNumber.payabliCaptureDigitsOnly.count == PayabliPayInInputLimits.routingNumberDigits
        case .accountNumber:
            return (PayabliPayInInputLimits.minimumAccountNumberDigits ... PayabliPayInInputLimits
                .maximumAccountNumberDigits)
                .contains(accountNumber.payabliCaptureDigitsOnly.count)
        case .accountType:
            return true
        case .accountHolderType:
            return fieldIsVisible(.accountHolderType) || configuration.hiddenValues.accountHolderType != nil
        case .secCode:
            return true
        case .deviceId:
            return !deviceId.payabliCaptureTrimmed.isEmpty || configuration.hiddenValues.deviceId?.payabliCaptureTrimmed
                .payabliCaptureNilIfEmpty != nil
        default:
            return true
        }
    }

    private func customerFieldHasRequiredValue(_ field: PayabliPayInField) -> Bool {
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

    private func paymentFieldHasRequiredValue(_ field: PayabliPayInField) -> Bool {
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
        cardNumberStorage = ""
        cardExpiration = ""
        cardExpirationMonth = nil
        cardExpirationYear = nil
        cardCvvStorage = ""
        achRoutingStorage = ""
        achAccountStorage = ""
    }

    private static func message(for error: Error) -> String {
        let message: String = if let payabliError = error as? any PayabliError {
            if let detail = payabliError.detail?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty, detail != payabliError.reason {
                "\(payabliError.reason)\n\(detail)"
            } else {
                payabliError.reason
            }
        } else {
            String(describing: error)
        }
        return PayabliPayInSensitiveDataRedactor.redact(message)
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

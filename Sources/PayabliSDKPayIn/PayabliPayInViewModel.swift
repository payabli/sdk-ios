import Foundation
import PayabliSDKCore
import SwiftUI

@MainActor
final class PayabliPayInViewModel: ObservableObject {
    @Published var selectedMethod: PayabliPayInMethodType {
        didSet { dropMarksOffScreen() }
    }

    @Published var cardholderNameStorage = "" {
        didSet { acceptEdit(of: .cardholderName) }
    }

    @Published var cardNumberStorage = "" {
        didSet { acceptEdit(of: .cardNumber) }
    }

    @Published var cardExpiration = ""

    @Published var cardExpirationMonth: Int?

    @Published var cardExpirationYear: Int?

    @Published var cardCvvStorage = "" {
        didSet { acceptEdit(of: .cardCvv) }
    }

    @Published var cardZipStorage = "" {
        didSet { acceptEdit(of: .cardZip) }
    }

    @Published var achHolderStorage = "" {
        didSet { acceptEdit(of: .accountHolder) }
    }

    @Published var achRoutingStorage = "" {
        didSet { acceptEdit(of: .routingNumber) }
    }

    @Published var achAccountStorage = "" {
        didSet { acceptEdit(of: .accountNumber) }
    }

    /// A pick clears its mark even when the value is unchanged, because the menu reports every tap,
    /// including the one on the standing option, and the mark answers the tap rather than the change.
    @Published var accountType: PayabliPayInAccountType = .checking {
        didSet { acceptEdit(of: .accountType) }
    }

    @Published var accountHolderType: PayabliPayInAccountHolderType = .personal {
        didSet { acceptEdit(of: .accountHolderType) }
    }

    @Published var secCode: PayabliPayInSecCode = .web {
        didSet { acceptEdit(of: .secCode) }
    }

    @Published var deviceId = "" {
        didSet { acceptEdit(of: .deviceId) }
    }

    @Published var methodDescription = ""
    @Published var firstName = "" {
        didSet { acceptEdit(of: .firstName) }
    }

    @Published var lastName = "" {
        didSet { acceptEdit(of: .lastName) }
    }

    @Published var customerNumber = "" {
        didSet { acceptEdit(of: .customerNumber) }
    }

    @Published var billingEmail = "" {
        didSet { acceptEdit(of: .billingEmail) }
    }

    @Published var billingZipStorage = "" {
        didSet { acceptEdit(of: .billingZip) }
    }

    @Published private(set) var isSubmitting = false
    /// The operation the submission in flight is sending, or nil when none is.
    @Published private(set) var submittingOperation: PayabliPayInOperation?
    @Published private(set) var errorMessage: String?
    /// The fields the last refusal named, until the payer edits one or its box leaves the screen.
    @Published var rejectedFields: Set<PayabliPayInField> = []

    private(set) var component: PayabliPayIn
    var configuration: PayabliPayInFormConfiguration
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
        // A new component is a new payment flow, so the last flow's refusal describes nothing on it.
        let replacesFlow = component !== self.component
        self.component = component
        self.configuration = configuration
        lifecycleSignature = nextSignature
        if replacesFlow {
            clearMarks()
        }

        let methods = availableMethods
        if !methods.contains(selectedMethod) {
            selectedMethod = methods.contains(configuration.defaultMethod)
                ? configuration.defaultMethod
                : methods[0]
        }
        dropValuesWithoutAField()
        dropMarksOffScreen()
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
            field != .amount && field != .serviceFee && field != .surchargeFee
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

    var hasMarkedFieldOnScreen: Bool {
        !rejectedFields.isDisjoint(with: activeFields)
    }

    var canSubmit: Bool {
        guard !hasMarkedFieldOnScreen else { return false }
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
        clearMarks()
        guard !isSubmitting else {
            let error = PayabliPayInError.submissionInProgress
            errorMessage = Self.message(for: error)
            throw error
        }
        isSubmitting = true
        submittingOperation = component.operation
        defer {
            isSubmitting = false
            submittingOperation = nil
        }
        let submittedFlow = component

        // Refused before anything else, and without clearing what the payer typed: only the host can change it.
        if component.operation != .storePaymentMethod, let details = component.requestConfiguration?.paymentDetails {
            do {
                try details.validate()
            } catch {
                errorMessage = Self.message(for: error)
                throw error
            }
        }

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
            // After the clear, because its edits take a mark off. A refusal of a flow replaced while
            // it was in flight marks nothing.
            if component === submittedFlow {
                rejectedFields = PayabliPayInRejectedFields.fields(in: error).intersection(activeFields)
            }
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
        // The wheel is the payer's pick, so an assignment here answers a mark. The pre-fill
        // that opens the wheel assigns too, and answers nothing.
        acceptEdit(of: .cardExpiration)
    }

    func selectExpirationYear(_ year: Int) {
        cardExpirationYear = year
        synchronizeExpirationText()
        acceptEdit(of: .cardExpiration)
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

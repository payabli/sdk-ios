import PayabliSDKCore
import SwiftUI

@MainActor
public final class PayabliPaymentMethodViewModel: ObservableObject {
    @Published public var selectedMethod: PayabliPaymentMethodType
    @Published private var cardholderNameStorage = ""
    @Published private var cardNumberStorage = ""

    @Published public var cardExpiration = ""
    @Published public var cardExpirationMonth: Int?
    @Published public var cardExpirationYear: Int?
    @Published private var cardCvvStorage = ""
    @Published private var cardZipStorage = ""
    @Published private var achHolderStorage = ""
    @Published private var achRoutingStorage = ""
    @Published private var achAccountStorage = ""

    @Published public var achAccountType: PayabliACHAccountType = .checking
    @Published public var achHolderType: PayabliACHHolderType = .personal
    @Published public var achSecCode: PayabliACHSecCode = .web
    @Published public var achDevice = ""
    @Published public var methodDescription = ""
    @Published public var firstName = ""
    @Published public var lastName = ""
    @Published public var customerNumber = ""
    @Published public var billingEmail = ""
    @Published private var billingZipStorage = ""

    @Published public private(set) var isSubmitting = false
    @Published public private(set) var errorMessage: String?

    private let component: PayabliPaymentMethod
    private let configuration: PayabliPaymentMethodFormConfiguration

    public init(
        component: PayabliPaymentMethod,
        configuration: PayabliPaymentMethodFormConfiguration = PayabliPaymentMethodFormConfiguration()
    ) {
        self.component = component
        self.configuration = configuration
        self.selectedMethod = configuration.defaultMethod
    }

    public var cardholderName: String {
        get { cardholderNameStorage }
        set {
            let limited = limitCardholderName(newValue)
            guard cardholderNameStorage != limited else { return }
            cardholderNameStorage = limited
        }
    }

    public var cardNumber: String {
        get { cardNumberStorage }
        set {
            let formatted = formatCardNumber(newValue)
            guard cardNumberStorage != formatted else { return }
            cardNumberStorage = formatted
        }
    }

    public var cardCvv: String {
        get { cardCvvStorage }
        set {
            let limited = limitCardCvv(newValue)
            guard cardCvvStorage != limited else { return }
            cardCvvStorage = limited
        }
    }

    public var cardZip: String {
        get { cardZipStorage }
        set {
            let limited = limitPostalCode(newValue)
            guard cardZipStorage != limited else { return }
            cardZipStorage = limited
        }
    }

    public var achHolder: String {
        get { achHolderStorage }
        set {
            let limited = limitACHHolderName(newValue)
            guard achHolderStorage != limited else { return }
            achHolderStorage = limited
        }
    }

    public var achRouting: String {
        get { achRoutingStorage }
        set {
            let limited = limitACHRouting(newValue)
            guard achRoutingStorage != limited else { return }
            achRoutingStorage = limited
        }
    }

    public var achAccount: String {
        get { achAccountStorage }
        set {
            let limited = limitACHAccount(newValue)
            guard achAccountStorage != limited else { return }
            achAccountStorage = limited
        }
    }

    public var billingZip: String {
        get { billingZipStorage }
        set {
            let limited = limitPostalCode(newValue)
            guard billingZipStorage != limited else { return }
            billingZipStorage = limited
        }
    }

    public var activeFields: [PayabliPaymentMethodField] {
        switch selectedMethod {
        case .card:
            return configuration.cardFieldOrder
        case .ach:
            return configuration.achFieldOrder
        }
    }

    public var detectedCardBrand: PayabliPaymentMethodCardBrand {
        PayabliPaymentMethodCardBrand.detect(cardNumber: cardNumber)
    }

    public var cardNumberValidationMessage: String? {
        let digits = cardNumber.digitsOnly
        guard configuration.options.validation.requiresLuhnCheck,
              digits.count >= PayabliPaymentMethodInputLimits.minimumCardNumberDigits,
              !PayabliCardPaymentMethodData.passesLuhn(digits)
        else {
            return nil
        }

        return "Invalid Card Number"
    }

    public var expirationDisplayText: String {
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

    public var hasSelectedExpiration: Bool {
        selectedExpirationMonth != nil || selectedExpirationYear != nil
    }

    public var canSubmit: Bool {
        switch selectedMethod {
        case .card:
            return fieldHasRequiredValue(.cardholderName)
                && fieldHasRequiredValue(.cardNumber)
                && cardNumberValidationMessage == nil
                && cardExpiration.digitsOnly.count >= 4
                && fieldHasRequiredValue(.cardCvv)
                && fieldHasRequiredValue(.cardZip)
                && requiredFieldsAreSatisfied
        case .ach:
            return fieldHasRequiredValue(.achHolder)
                && fieldHasRequiredValue(.achRouting)
                && fieldHasRequiredValue(.achAccount)
                && requiredFieldsAreSatisfied
        }
    }

    public func submit() async throws -> PayabliStoredPaymentMethod {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        let submittedPaymentMethod = paymentMethod()

        do {
            try validateRequiredFields()
            let result = try await component.addPaymentMethod(
                submittedPaymentMethod,
                options: mergedOptions()
            )
            clearSensitiveFields()
            return result
        } catch {
            clearFieldsAfterFailure(for: submittedPaymentMethod)
            errorMessage = Self.message(for: error)
            throw error
        }
    }

    public func formatCardNumber(_ value: String) -> String {
        let digits = String(value.digitsOnly.prefix(PayabliPaymentMethodInputLimits.maximumCardNumberDigits))
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
        String(value.prefix(PayabliPaymentMethodInputLimits.maximumCardholderNameCharacters))
    }

    func limitCardCvv(_ value: String) -> String {
        String(value.digitsOnly.prefix(PayabliPaymentMethodInputLimits.maximumCardCvvDigits))
    }

    func limitPostalCode(_ value: String) -> String {
        String(value.prefix(PayabliPaymentMethodInputLimits.maximumPostalCodeCharacters))
    }

    func limitACHHolderName(_ value: String) -> String {
        String(value.prefix(PayabliPaymentMethodInputLimits.maximumACHHolderNameCharacters))
    }

    func limitACHRouting(_ value: String) -> String {
        String(value.digitsOnly.prefix(PayabliPaymentMethodInputLimits.achRoutingDigits))
    }

    func limitACHAccount(_ value: String) -> String {
        String(value.digitsOnly.prefix(PayabliPaymentMethodInputLimits.maximumACHAccountDigits))
    }

    public func formatExpiration(_ value: String) -> String {
        let digits = String(value.digitsOnly.prefix(4))
        guard digits.count > 2 else { return digits }
        let month = digits.prefix(2)
        let year = digits.dropFirst(2)
        return "\(month)\(configuration.formatting.expirationSeparator)\(year)"
    }

    public func selectExpirationMonth(_ month: Int) {
        cardExpirationMonth = min(max(month, 1), 12)
        synchronizeExpirationText()
    }

    public func selectExpirationYear(_ year: Int) {
        cardExpirationYear = year
        synchronizeExpirationText()
    }

    public func ensureExpirationSelection(defaultDate: Date = Date()) {
        let calendar = Calendar.current
        if cardExpirationMonth == nil {
            cardExpirationMonth = selectedExpirationMonth ?? calendar.component(.month, from: defaultDate)
        }
        if cardExpirationYear == nil {
            cardExpirationYear = selectedExpirationYear ?? calendar.component(.year, from: defaultDate)
        }
        synchronizeExpirationText()
    }

    private func paymentMethod() -> PayabliPaymentMethodInput {
        switch selectedMethod {
        case .card:
            return .card(PayabliCardPaymentMethodData(
                cardNumber: cardNumber,
                expiration: cardExpiration,
                cardholderName: cardholderName,
                cvv: cardCvv,
                billingZip: cardZip
            ))
        case .ach:
            return .ach(PayabliACHPaymentMethodData(
                accountNumber: achAccount,
                accountType: achAccountType,
                holderName: achHolder,
                routingNumber: achRouting,
                secCode: configuration.hiddenValues.achSecCode ?? .web,
                holderType: fieldIsVisible(.achHolderType) ? achHolderType : configuration.hiddenValues.achHolderType,
                device: fieldIsVisible(.achDevice) ? achDevice : configuration.hiddenValues.achDevice
            ))
        }
    }

    private func mergedOptions() -> PayabliPaymentMethodOptions {
        var options = configuration.options
        if let hiddenDescription = configuration.hiddenValues.methodDescription?.trimmed.nilIfEmpty {
            options.methodDescription = hiddenDescription
        }
        if let description = methodDescription.trimmed.nilIfEmpty {
            options.methodDescription = description
        }
        if let customer = mergedCustomerData() {
            options.customerData = customer
        }
        return options
    }

    private func mergedCustomerData() -> PayabliPaymentMethodCustomerData? {
        var customer = configuration.options.customerData ?? PayabliPaymentMethodCustomerData()
        if let hiddenCustomer = configuration.hiddenValues.customerData {
            customer.merge(hiddenCustomer)
        }
        customer.apply(\.firstName, firstName.trimmed.nilIfEmpty)
        customer.apply(\.lastName, lastName.trimmed.nilIfEmpty)
        customer.apply(\.customerNumber, customerNumber.trimmed.nilIfEmpty)
        customer.apply(\.billingEmail, billingEmail.trimmed.nilIfEmpty)
        customer.apply(\.billingZip, billingZip.trimmed.nilIfEmpty)
        return customer.hasAnyValue ? customer : nil
    }

    private func fieldIsVisible(_ field: PayabliPaymentMethodField) -> Bool {
        activeFields.contains(field)
    }

    private var requiredFieldsAreSatisfied: Bool {
        configuration.requiredFields
            .filter { activeFields.contains($0) }
            .allSatisfy(fieldHasRequiredValue)
    }

    private func validateRequiredFields() throws {
        for field in configuration.requiredFields where activeFields.contains(field) {
            guard fieldHasRequiredValue(field) else {
                throw PayabliPaymentMethodError.invalidInput("\(configuration.labels.label(for: field)) is required.")
            }
        }
    }

    private func fieldHasRequiredValue(_ field: PayabliPaymentMethodField) -> Bool {
        switch field {
        case .cardholderName:
            let value = cardholderName.trimmed
            return !value.isEmpty
                && value.count <= PayabliPaymentMethodInputLimits.maximumCardholderNameCharacters
        case .cardNumber:
            return (PayabliPaymentMethodInputLimits.minimumCardNumberDigits ... PayabliPaymentMethodInputLimits.maximumCardNumberDigits)
                .contains(cardNumber.digitsOnly.count)
                && cardNumberValidationMessage == nil
        case .cardExpiration:
            return cardExpiration.digitsOnly.count >= 4
        case .cardCvv:
            return (PayabliPaymentMethodInputLimits.minimumCardCvvDigits ... PayabliPaymentMethodInputLimits.maximumCardCvvDigits)
                .contains(cardCvv.digitsOnly.count)
        case .cardZip:
            let value = cardZip.trimmed
            return !value.isEmpty
                && value.count <= PayabliPaymentMethodInputLimits.maximumPostalCodeCharacters
        case .achHolder:
            let value = achHolder.trimmed
            return !value.isEmpty
                && value.count <= PayabliPaymentMethodInputLimits.maximumACHHolderNameCharacters
        case .achRouting:
            return achRouting.digitsOnly.count == PayabliPaymentMethodInputLimits.achRoutingDigits
        case .achAccount:
            return (PayabliPaymentMethodInputLimits.minimumACHAccountDigits ... PayabliPaymentMethodInputLimits.maximumACHAccountDigits)
                .contains(achAccount.digitsOnly.count)
        case .achAccountType, .achHolderType, .achSecCode:
            return true
        case .achDevice:
            return !achDevice.trimmed.isEmpty
        case .methodDescription:
            return !methodDescription.trimmed.isEmpty
        case .firstName:
            return !firstName.trimmed.isEmpty
        case .lastName:
            return !lastName.trimmed.isEmpty
        case .customerNumber:
            return !customerNumber.trimmed.isEmpty
        case .billingEmail:
            return !billingEmail.trimmed.isEmpty
        case .billingZip:
            return !billingZip.trimmed.isEmpty
        }
    }

    private func clearSensitiveFields() {
        cardNumber = ""
        cardExpiration = ""
        cardExpirationMonth = nil
        cardExpirationYear = nil
        cardCvv = ""
        achRouting = ""
        achAccount = ""
    }

    private func clearFieldsAfterFailure(for paymentMethod: PayabliPaymentMethodInput) {
        switch paymentMethod {
        case .card:
            cardCvv = ""
        case .ach:
            break
        }
    }

    private var selectedExpirationMonth: Int? {
        if let cardExpirationMonth {
            return cardExpirationMonth
        }

        let digits = cardExpiration.digitsOnly
        guard digits.count >= 2,
              let month = Int(String(digits.prefix(2))),
              (1 ... 12).contains(month)
        else {
            return nil
        }
        return month
    }

    private var selectedExpirationYear: Int? {
        if let cardExpirationYear {
            return cardExpirationYear
        }

        let digits = cardExpiration.digitsOnly
        guard digits.count >= 4,
              let shortYear = Int(String(digits.suffix(2)))
        else {
            return nil
        }

        let currentYear = Calendar.current.component(.year, from: Date())
        let currentCentury = currentYear - currentYear % 100
        let candidate = currentCentury + shortYear
        return candidate < currentYear ? candidate + 100 : candidate
    }

    private func synchronizeExpirationText() {
        guard let month = cardExpirationMonth, let year = cardExpirationYear else {
            cardExpiration = ""
            return
        }

        cardExpiration = String(format: "%02d/%02d", month, year % 100)
    }

    private static func message(for error: Error) -> String {
        if let payabliError = error as? any PayabliError {
            if let detail = payabliError.detail?.trimmed.nilIfEmpty, detail != payabliError.reason {
                return "\(payabliError.reason)\n\(detail)"
            }
            return payabliError.reason
        }
        return String(describing: error)
    }
}

private extension PayabliPaymentMethodCustomerData {
    mutating func merge(_ override: PayabliPaymentMethodCustomerData) {
        apply(\.additionalData, override.additionalData)
        apply(\.billingAddress1, override.billingAddress1)
        apply(\.billingAddress2, override.billingAddress2)
        apply(\.billingCity, override.billingCity)
        apply(\.billingCountry, override.billingCountry)
        apply(\.billingEmail, override.billingEmail)
        apply(\.billingPhone, override.billingPhone)
        apply(\.billingState, override.billingState)
        apply(\.billingZip, override.billingZip)
        apply(\.company, override.company)
        apply(\.customerId, override.customerId)
        apply(\.customerNumber, override.customerNumber)
        apply(\.firstName, override.firstName)
        apply(\.identifierFields, override.identifierFields)
        apply(\.lastName, override.lastName)
        apply(\.shippingAddress1, override.shippingAddress1)
        apply(\.shippingAddress2, override.shippingAddress2)
        apply(\.shippingCity, override.shippingCity)
        apply(\.shippingCountry, override.shippingCountry)
        apply(\.shippingState, override.shippingState)
        apply(\.shippingZip, override.shippingZip)
    }

    mutating func apply<Value>(_ keyPath: WritableKeyPath<Self, Value?>, _ value: Value?) {
        if let value {
            self[keyPath: keyPath] = value
        }
    }

    var hasAnyValue: Bool {
        let stringValues = [
            billingAddress1,
            billingAddress2,
            billingCity,
            billingCountry,
            billingEmail,
            billingPhone,
            billingState,
            billingZip,
            company,
            customerNumber,
            firstName,
            lastName,
            shippingAddress1,
            shippingAddress2,
            shippingCity,
            shippingCountry,
            shippingState,
            shippingZip
        ]

        return additionalData?.isEmpty == false
            || customerId != nil
            || identifierFields?.isEmpty == false
            || stringValues.contains { $0?.nilIfEmpty != nil }
    }
}

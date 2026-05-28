import PayabliSDKCore
import SwiftUI

@MainActor
public final class PayabliPaymentMethodViewModel: ObservableObject {
    @Published public var selectedMethod: PayabliPaymentMethodType
    @Published public var cardholderName = ""
    @Published public var cardNumber = ""
    @Published public var cardExpiration = ""
    @Published public var cardExpirationMonth: Int?
    @Published public var cardExpirationYear: Int?
    @Published public var cardCvv = ""
    @Published public var cardZip = ""
    @Published public var achHolder = ""
    @Published public var achRouting = ""
    @Published public var achAccount = ""
    @Published public var achAccountType: PayabliACHAccountType = .checking
    @Published public var achHolderType: PayabliACHHolderType = .personal
    @Published public var achSecCode: PayabliACHSecCode = .web
    @Published public var achDevice = ""
    @Published public var methodDescription = ""
    @Published public var firstName = ""
    @Published public var lastName = ""
    @Published public var customerNumber = ""
    @Published public var billingEmail = ""
    @Published public var billingZip = ""
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
              digits.count >= 12,
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
            return !cardholderName.trimmed.isEmpty
                && cardNumber.digitsOnly.count >= 12
                && cardNumberValidationMessage == nil
                && cardExpiration.digitsOnly.count >= 4
                && (3 ... 4).contains(cardCvv.digitsOnly.count)
                && !cardZip.trimmed.isEmpty
                && requiredFieldsAreSatisfied
        case .ach:
            return !achHolder.trimmed.isEmpty
                && achRouting.digitsOnly.count == 9
                && achAccount.digitsOnly.count >= 4
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
        let digits = String(value.digitsOnly.prefix(19))
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
            return !cardholderName.trimmed.isEmpty
        case .cardNumber:
            return cardNumber.digitsOnly.count >= 12 && cardNumberValidationMessage == nil
        case .cardExpiration:
            return cardExpiration.digitsOnly.count >= 4
        case .cardCvv:
            return (3 ... 4).contains(cardCvv.digitsOnly.count)
        case .cardZip:
            return !cardZip.trimmed.isEmpty
        case .achHolder:
            return !achHolder.trimmed.isEmpty
        case .achRouting:
            return achRouting.digitsOnly.count == 9
        case .achAccount:
            return achAccount.digitsOnly.count >= 4
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

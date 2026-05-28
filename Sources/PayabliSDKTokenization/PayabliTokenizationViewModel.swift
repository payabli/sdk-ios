import PayabliSDKCore
import SwiftUI

@MainActor
public final class PayabliTokenizationViewModel: ObservableObject {
    @Published public var selectedMethod: PayabliTokenizationMethod
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

    private let component: PayabliTokenization
    private let configuration: PayabliTokenizationFormConfiguration

    public init(
        component: PayabliTokenization,
        configuration: PayabliTokenizationFormConfiguration = PayabliTokenizationFormConfiguration()
    ) {
        self.component = component
        self.configuration = configuration
        self.selectedMethod = configuration.defaultMethod
    }

    public var activeFields: [PayabliTokenizationField] {
        switch selectedMethod {
        case .card:
            return configuration.cardFieldOrder
        case .ach:
            return configuration.achFieldOrder
        }
    }

    public var detectedCardBrand: PayabliTokenizationCardBrand {
        PayabliTokenizationCardBrand.detect(cardNumber: cardNumber)
    }

    public var cardNumberValidationMessage: String? {
        let digits = cardNumber.digitsOnly
        guard configuration.options.validation.requiresLuhnCheck,
              digits.count >= 12,
              !PayabliCardTokenizationData.passesLuhn(digits)
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
                && !cardZip.trimmed.isEmpty
        case .ach:
            return !achHolder.trimmed.isEmpty
                && achRouting.digitsOnly.count == 9
                && achAccount.digitsOnly.count >= 4
        }
    }

    public func submit() async throws -> PayabliTokenizedMethod {
        errorMessage = nil
        isSubmitting = true
        defer { isSubmitting = false }
        let submittedPaymentMethod = paymentMethod()

        do {
            let result = try await component.tokenize(
                paymentMethod: submittedPaymentMethod,
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

    private func paymentMethod() -> PayabliTokenizationPaymentMethod {
        switch selectedMethod {
        case .card:
            return .card(PayabliCardTokenizationData(
                cardNumber: cardNumber,
                expiration: cardExpiration,
                cardholderName: cardholderName,
                cvv: fieldIsVisible(.cardCvv) ? cardCvv : configuration.hiddenValues.cardCvv,
                billingZip: cardZip
            ))
        case .ach:
            return .ach(PayabliACHTokenizationData(
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

    private func mergedOptions() -> PayabliTokenizationOptions {
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

    private func mergedCustomerData() -> PayabliTokenizationCustomerData? {
        var customer = configuration.options.customerData ?? PayabliTokenizationCustomerData()
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

    private func fieldIsVisible(_ field: PayabliTokenizationField) -> Bool {
        activeFields.contains(field)
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

    private func clearFieldsAfterFailure(for paymentMethod: PayabliTokenizationPaymentMethod) {
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

private extension PayabliTokenizationCustomerData {
    mutating func merge(_ override: PayabliTokenizationCustomerData) {
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

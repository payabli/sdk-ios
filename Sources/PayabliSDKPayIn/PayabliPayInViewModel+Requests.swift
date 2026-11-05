import Foundation
import PayabliSDKCore

extension PayabliPayInViewModel {
    /// The form's sensitive buffers for one submission, closed together once the submission ends.
    final class FormBufferRegistry {
        private var buffers: [SensitiveDigits] = []

        /// Holds a copy of the supplied digits, registered so `close()` overwrites them too.
        ///
        /// - Parameter digits: the digits to hold a copy of.
        /// - Returns: the value holding a copy of `digits`, registered here.
        func of(_ digits: [UInt8]) -> SensitiveDigits {
            let value = SensitiveDigits.of(digits)
            buffers.append(value)
            return value
        }

        /// For digits that are already a `String`, typically from a text field, registered so
        /// `close()` overwrites them too.
        ///
        /// - Parameter source: the digits as a `String`, which this cannot unmake.
        /// - Returns: the value holding the digits, registered here.
        func ofString(_ source: String) -> SensitiveDigits {
            let value = SensitiveDigits.ofString(source)
            buffers.append(value)
            return value
        }

        /// Closes every registered buffer. Idempotent, so a submission that already closed them is
        /// not an error.
        func close() {
            for buffer in buffers {
                buffer.close()
            }
            buffers = []
        }
    }

    /// Runs `body` with a registry of the form's sensitive buffers, closing them all once it ends.
    ///
    /// - Parameter body: the submission, which takes its buffers from the registry.
    /// - Returns: what `body` returned.
    func withFormBuffers<T>(_ body: (FormBufferRegistry) async throws -> T) async rethrows -> T {
        let registry = FormBufferRegistry()
        defer { registry.close() }
        return try await body(registry)
    }

    /// The expiry as the form sends it, with the configured separator after the month read as `/`. It is
    /// matched by Unicode scalar, because a combining mark joins the month's second digit.
    var submittedExpiration: String {
        let separator = configuration.formatting.expirationSeparator.unicodeScalars
        let scalars = cardExpiration.unicodeScalars
        let afterMonth = scalars.dropFirst(2)
        guard afterMonth.starts(with: separator) else { return cardExpiration }
        var expiry = String.UnicodeScalarView(scalars.prefix(2))
        expiry.append("/")
        expiry.append(contentsOf: afterMonth.dropFirst(separator.count))
        return String(expiry)
    }

    /// The form's expiry as a month and a four-digit year, read from ``submittedExpiration`` as `MM/YY` in
    /// 2000 to 2099. Text that isn't four ASCII digits reads as month 0 and year 0, which the card's own check
    /// refuses before anything is sent.
    var submittedExpiry: (month: Int, year: Int) {
        guard let digits = submittedExpiration.payabliInstrumentDigits, digits.count == 4,
              let month = Int(digits.prefix(2)), let year = Int(digits.suffix(2))
        else { return (0, 0) }
        return (month, 2000 + year)
    }

    /// The fields `method` draws for this operation.
    ///
    /// - Parameter method: the method whose fields to list.
    /// - Returns: the method's fields in their configured order, without the amounts when saving a method.
    func fields(for method: PayabliPayInMethodType) -> [PayabliPayInField] {
        let fields = switch method {
        case .card:
            configuration.cardFieldOrder
        case .bankAccount:
            configuration.bankFieldOrder
        }

        guard case .storePaymentMethod = operation else { return fields }
        return fields.filter { field in
            field != .amount && field != .serviceFee && field != .surchargeFee
        }
    }

    func methodInput(_ method: PayabliPayInMethodType, with buffers: FormBufferRegistry) -> PayabliPayInMethodInput {
        switch method {
        case .card:
            return .card(PayabliPayInCardData(
                cardNumber: buffers.ofString(cardNumber),
                expiryMonth: submittedExpiry.month,
                expiryYear: submittedExpiry.year,
                securityCode: buffers.ofString(cardCvv),
                holderName: cardholderName,
                postalCode: cardZip
            ))
        case .bankAccount:
            return .bankAccount(PayabliPayInBankAccountData(
                accountNumber: buffers.ofString(accountNumber),
                routingNumber: routingNumber,
                accountType: accountType,
                holderName: accountHolder,
                holderType: fieldIsVisible(.accountHolderType) ? accountHolderType : configuration.hiddenValues.accountHolderType,
                secCode: configuration.hiddenValues.secCode,
                deviceId: fieldIsVisible(.deviceId) ? deviceId : configuration.hiddenValues.deviceId
            ))
        }
    }

    func paymentMethod(_ method: PayabliPayInMethodType, with buffers: FormBufferRegistry) -> PayabliPayInPaymentMethod {
        switch method {
        case .card:
            return .card(PayabliPayInPaymentMethod.Card(
                data: PayabliPayInCardData(
                    cardNumber: buffers.ofString(cardNumber),
                    expiryMonth: submittedExpiry.month,
                    expiryYear: submittedExpiry.year,
                    securityCode: buffers.ofString(cardCvv),
                    holderName: cardholderName,
                    postalCode: cardZip
                )
            ))
        case .bankAccount:
            return .bankAccount(PayabliPayInPaymentMethod.BankAccount(
                data: PayabliPayInBankAccountData(
                    accountNumber: buffers.ofString(accountNumber),
                    routingNumber: routingNumber,
                    accountType: accountType,
                    holderName: accountHolder,
                    holderType: fieldIsVisible(.accountHolderType) ? accountHolderType : configuration.hiddenValues.accountHolderType,
                    secCode: configuration.hiddenValues.secCode,
                    deviceId: fieldIsVisible(.deviceId) ? deviceId : configuration.hiddenValues.deviceId
                )
            ))
        }
    }

    func mergedCustomerData() -> PayabliPayInCustomerData? {
        var customer = operation.requestConfiguration?.customerData
            ?? operation.storeOptions?.customerData
            ?? PayabliPayInCustomerData()
        customer.payabliCaptureMerge(configuration.hiddenValues.customerData)
        customer.payabliCaptureApply(\.firstName, firstName.payabliCaptureTrimmed.payabliCaptureNilIfEmpty)
        customer.payabliCaptureApply(\.lastName, lastName.payabliCaptureTrimmed.payabliCaptureNilIfEmpty)
        customer.payabliCaptureApply(\.customerNumber, customerNumber.payabliCaptureTrimmed.payabliCaptureNilIfEmpty)
        customer.payabliCaptureApply(\.billingEmail, billingEmail.payabliCaptureTrimmed.payabliCaptureNilIfEmpty)
        customer.payabliCaptureApply(\.billingZip, billingZip.payabliCaptureTrimmed.payabliCaptureNilIfEmpty)
        return customer.payabliCaptureHasAnyValue ? customer : nil
    }

    func mergedOrderDescription() -> String? {
        methodDescription.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
            ?? configuration.hiddenValues.methodDescription?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
    }

    func mergedStoreOptions() -> PayabliPayInStoreOptions {
        var options = operation.storeOptions ?? PayabliPayInStoreOptions()
        options.customerData = mergedCustomerData()
        options.methodDescription = mergedOrderDescription()
            ?? options.methodDescription?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
        return options
    }

    private func fieldIsVisible(_ field: PayabliPayInField) -> Bool {
        activeFields.contains(field)
    }

    /// Every field the configuration offers a box for, on any method the form offers the payer.
    ///
    /// A field on the instrument the payer is not on still counts: its tab is where the payer
    /// corrects it, so a value for it is not held out of sight.
    private var fieldsWithABox: Set<PayabliPayInField> {
        var fields = Set<PayabliPayInField>()
        if availableMethods.contains(.card) {
            fields.formUnion(configuration.cardFieldOrder)
        }
        if availableMethods.contains(.bankAccount) {
            fields.formUnion(configuration.bankFieldOrder)
        }
        return fields
    }

    /// Drops what the payer typed into a field the configuration no longer offers, writing nothing when
    /// nothing was held. Host-supplied hidden values are untouched.
    func dropValuesWithoutAField() {
        dropValues(for: Set(PayabliPayInField.allCases).subtracting(fieldsWithABox))
    }

    /// What the payer typed into a field only the method they left shows goes, because it is never
    /// submitted with the method they moved to and is no longer on screen. A field both methods show
    /// is kept.
    ///
    /// - Parameter previous: The method the payer moved away from.
    func dropValuesLeftBehind(by previous: PayabliPayInMethodType) {
        dropValues(for: Set(fields(of: previous)).subtracting(fields(of: selectedMethod)))
    }

    private func fields(of method: PayabliPayInMethodType) -> [PayabliPayInField] {
        switch method {
        case .card:
            configuration.cardFieldOrder
        case .bankAccount:
            configuration.bankFieldOrder
        }
    }

    private func dropValues(for dropped: Set<PayabliPayInField>) {
        dropCardValues(dropped)
        dropBankValues(dropped)
        dropCustomerValues(dropped)
    }

    private func dropCardValues(_ dropped: Set<PayabliPayInField>) {
        if dropped.contains(.cardholderName), !cardholderNameStorage.isEmpty {
            cardholderNameStorage = ""
        }
        if dropped.contains(.cardNumber), !cardNumberStorage.isEmpty {
            cardNumberStorage = ""
        }
        if dropped.contains(.cardExpiration),
           !cardExpiration.isEmpty || cardExpirationMonth != nil || cardExpirationYear != nil
        {
            cardExpiration = ""
            cardExpirationMonth = nil
            cardExpirationYear = nil
        }
        if dropped.contains(.cardSecurityCode), !cardCvvStorage.isEmpty {
            cardCvvStorage = ""
        }
        if dropped.contains(.cardPostalCode), !cardZipStorage.isEmpty {
            cardZipStorage = ""
        }
    }

    private func dropBankValues(_ dropped: Set<PayabliPayInField>) {
        if dropped.contains(.accountHolder), !achHolderStorage.isEmpty {
            achHolderStorage = ""
        }
        if dropped.contains(.routingNumber), !achRoutingStorage.isEmpty {
            achRoutingStorage = ""
        }
        if dropped.contains(.accountNumber), !achAccountStorage.isEmpty {
            achAccountStorage = ""
        }
        if dropped.contains(.accountType), accountType != .checking {
            accountType = .checking
        }
        if dropped.contains(.accountHolderType), accountHolderType != .personal {
            accountHolderType = .personal
        }
        if dropped.contains(.secCode), secCode != .web {
            secCode = .web
        }
        if dropped.contains(.deviceId), !deviceId.isEmpty {
            deviceId = ""
        }
    }

    private func dropCustomerValues(_ dropped: Set<PayabliPayInField>) {
        if dropped.contains(.methodDescription), !methodDescription.isEmpty {
            methodDescription = ""
        }
        if dropped.contains(.firstName), !firstName.isEmpty {
            firstName = ""
        }
        if dropped.contains(.lastName), !lastName.isEmpty {
            lastName = ""
        }
        if dropped.contains(.customerNumber), !customerNumber.isEmpty {
            customerNumber = ""
        }
        if dropped.contains(.billingEmail), !billingEmail.isEmpty {
            billingEmail = ""
        }
        if dropped.contains(.billingPostalCode), !billingZipStorage.isEmpty {
            billingZipStorage = ""
        }
    }

    var requiredFieldsAreSatisfied: Bool {
        activeRequiredFields.allSatisfy(fieldHasRequiredValue)
    }

    func validateRequiredFields() throws {
        for field in activeRequiredFields {
            guard fieldHasRequiredValue(field) else {
                throw PayabliPayInError.invalidInput("\(labels.label(for: field)) is required.")
            }
        }
    }

    private var activeRequiredFields: [PayabliPayInField] {
        activeFields.filter { configuration.requiredFields.contains($0) }
    }

    func fieldHasRequiredValue(_ field: PayabliPayInField) -> Bool {
        switch field {
        case .cardholderName, .cardNumber, .cardExpiration, .cardSecurityCode, .cardPostalCode:
            return cardFieldHasRequiredValue(field)
        case .accountHolder, .routingNumber, .accountNumber, .accountType, .accountHolderType, .secCode, .deviceId:
            return achFieldHasRequiredValue(field)
        case .methodDescription, .firstName, .lastName, .customerNumber, .billingEmail, .billingPostalCode:
            return customerFieldHasRequiredValue(field)
        case .amount, .serviceFee, .surchargeFee:
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
                .contains(cardNumber.payabliInstrumentDigits?.count ?? 0)
                && cardNumberValidationMessage == nil
        case .cardExpiration:
            return (submittedExpiration.payabliInstrumentDigits?.count ?? 0) >= 4
        case .cardSecurityCode:
            return (PayabliPayInInputLimits.minimumCardCvvDigits ... PayabliPayInInputLimits.maximumCardCvvDigits)
                .contains(cardCvv.payabliInstrumentDigits?.count ?? 0)
        case .cardPostalCode:
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
            return routingNumber.payabliInstrumentDigits?.count == PayabliPayInInputLimits.routingNumberDigits
        case .accountNumber:
            return (PayabliPayInInputLimits.minimumAccountNumberDigits ... PayabliPayInInputLimits
                .maximumAccountNumberDigits)
                .contains(accountNumber.payabliInstrumentDigits?.count ?? 0)
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
        case .billingPostalCode:
            return !billingZip.payabliCaptureTrimmed.isEmpty
        default:
            return true
        }
    }

    private func paymentFieldHasRequiredValue(_ field: PayabliPayInField) -> Bool {
        switch field {
        case .amount, .serviceFee, .surchargeFee:
            // Present, not valid: an amount the request cannot send is refused at submission with its own message.
            return operation.requestConfiguration != nil
        default:
            return true
        }
    }

    func acceptEdit(of field: PayabliPayInField) {
        if rejectedFields.contains(field) {
            rejectedFields.remove(field)
        }
    }

    func clearMarks() {
        if !rejectedFields.isEmpty {
            rejectedFields = []
        }
    }

    func dropMarksOffScreen() {
        let onScreen = rejectedFields.intersection(activeFields)
        if onScreen != rejectedFields {
            rejectedFields = onScreen
        }
    }
}

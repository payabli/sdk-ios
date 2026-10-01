import Foundation
import PayabliSDKCore

extension PayabliPayInViewModel {
    func methodInput() -> PayabliPayInMethodInput {
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

    func paymentMethod() -> PayabliPayInPaymentMethod {
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

    func mergedCustomerData() -> PayabliPayInCustomerData? {
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

    func mergedOrderDescription() -> String? {
        methodDescription.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
            ?? configuration.hiddenValues.methodDescription?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
    }

    func mergedTokenStorageOptions() -> PayabliPayInTokenStorageOptions {
        var options = configuration.options
        options.customerData = mergedCustomerData()
        options.methodDescription = mergedOrderDescription()
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

    /// What the payer typed into a field no offered instrument shows any more goes with the field,
    /// so the form holds a value only while the configuration offers the field somewhere. Nothing
    /// is written when nothing was held, so an update a payer has not typed into publishes once.
    /// Host-supplied hidden values are not payer-typed and are untouched.
    func dropValuesWithoutAField() {
        let boxes = fieldsWithABox
        dropCardValuesWithoutABox(boxes)
        dropBankValuesWithoutABox(boxes)
        dropCustomerValuesWithoutABox(boxes)
    }

    private func dropCardValuesWithoutABox(_ boxes: Set<PayabliPayInField>) {
        if !boxes.contains(.cardholderName), !cardholderNameStorage.isEmpty {
            cardholderNameStorage = ""
        }
        if !boxes.contains(.cardNumber), !cardNumberStorage.isEmpty {
            cardNumberStorage = ""
        }
        if !boxes.contains(.cardExpiration),
           !cardExpiration.isEmpty || cardExpirationMonth != nil || cardExpirationYear != nil
        {
            cardExpiration = ""
            cardExpirationMonth = nil
            cardExpirationYear = nil
        }
        if !boxes.contains(.cardCvv), !cardCvvStorage.isEmpty {
            cardCvvStorage = ""
        }
        if !boxes.contains(.cardZip), !cardZipStorage.isEmpty {
            cardZipStorage = ""
        }
    }

    private func dropBankValuesWithoutABox(_ boxes: Set<PayabliPayInField>) {
        if !boxes.contains(.accountHolder), !achHolderStorage.isEmpty {
            achHolderStorage = ""
        }
        if !boxes.contains(.routingNumber), !achRoutingStorage.isEmpty {
            achRoutingStorage = ""
        }
        if !boxes.contains(.accountNumber), !achAccountStorage.isEmpty {
            achAccountStorage = ""
        }
        if !boxes.contains(.accountType), accountType != .checking {
            accountType = .checking
        }
        if !boxes.contains(.accountHolderType), accountHolderType != .personal {
            accountHolderType = .personal
        }
        if !boxes.contains(.secCode), secCode != .web {
            secCode = .web
        }
        if !boxes.contains(.deviceId), !deviceId.isEmpty {
            deviceId = ""
        }
    }

    private func dropCustomerValuesWithoutABox(_ boxes: Set<PayabliPayInField>) {
        if !boxes.contains(.methodDescription), !methodDescription.isEmpty {
            methodDescription = ""
        }
        if !boxes.contains(.firstName), !firstName.isEmpty {
            firstName = ""
        }
        if !boxes.contains(.lastName), !lastName.isEmpty {
            lastName = ""
        }
        if !boxes.contains(.customerNumber), !customerNumber.isEmpty {
            customerNumber = ""
        }
        if !boxes.contains(.billingEmail), !billingEmail.isEmpty {
            billingEmail = ""
        }
        if !boxes.contains(.billingZip), !billingZipStorage.isEmpty {
            billingZipStorage = ""
        }
    }

    var requiredFieldsAreSatisfied: Bool {
        activeRequiredFields.allSatisfy(fieldHasRequiredValue)
    }

    var operationConfigurationIsValid: Bool {
        if component.operation == .storePaymentMethod {
            return true
        }
        return paymentDetailsArePresent
    }

    private var paymentDetailsArePresent: Bool {
        // Present, not valid: an amount the request cannot send is refused at submission with its own message.
        component.requestConfiguration?.paymentDetails != nil
    }

    func validateRequiredFields() throws {
        for field in activeRequiredFields {
            guard fieldHasRequiredValue(field) else {
                throw PayabliPayInError.invalidInput("\(configuration.labels.label(for: field)) is required.")
            }
        }
    }

    private var activeRequiredFields: [PayabliPayInField] {
        activeFields.filter { configuration.requiredFields.contains($0) }
    }

    func fieldHasRequiredValue(_ field: PayabliPayInField) -> Bool {
        switch field {
        case .cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip:
            return cardFieldHasRequiredValue(field)
        case .accountHolder, .routingNumber, .accountNumber, .accountType, .accountHolderType, .secCode, .deviceId:
            return achFieldHasRequiredValue(field)
        case .methodDescription, .firstName, .lastName, .customerNumber, .billingEmail, .billingZip:
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
        case .amount, .serviceFee, .surchargeFee:
            return paymentDetailsArePresent
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

import Foundation
import PayabliSDKCore
import SwiftUI

@MainActor
final class PayabliPayInViewModel: ObservableObject {
    @Published var selectedMethod: PayabliPayInMethodType {
        didSet {
            if selectedMethod != oldValue {
                dropValuesLeftBehind(by: oldValue)
            }
            dropMarksOffScreen()
        }
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
        didSet { acceptEdit(of: .cardSecurityCode) }
    }

    @Published var cardZipStorage = "" {
        didSet { acceptEdit(of: .cardPostalCode) }
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

    /// A pick clears its mark even when the value is unchanged: the menu reports every tap, the standing
    /// option's included.
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
        didSet { acceptEdit(of: .billingPostalCode) }
    }

    @Published private(set) var isSubmitting = false
    /// The operation the submission in flight is sending, or nil when none is.
    @Published private(set) var submittingOperation: PayabliPayInOperation.Kind?
    @Published private(set) var failureMessage: String?
    /// The failure whose message is drawn, by the category and operation that picked its wording, so
    /// a change to the wording redraws the message already drawn. Cleared with the message.
    private var drawnFailure: (category: PayabliErrorCategory, operation: PayabliPayInOperation.Kind)?
    /// The fields the last refusal named, until the payer edits one or its box leaves the screen.
    @Published var rejectedFields: Set<PayabliPayInField> = []

    private(set) var component: PayabliPayIn
    /// The operation the form submits, which is the form's own: one form, one operation.
    private(set) var operation: PayabliPayInOperation
    var configuration: PayabliPayInFormConfiguration
    var labels: PayabliPayInFormLabels
    private var lifecycleSignature: String

    init(
        component: PayabliPayIn,
        operation: PayabliPayInOperation,
        configuration: PayabliPayInFormConfiguration = PayabliPayInFormConfiguration(),
        labels: PayabliPayInFormLabels = PayabliPayInFormLabels()
    ) {
        self.component = component
        self.operation = operation
        self.configuration = configuration
        self.labels = labels
        lifecycleSignature = Self.lifecycleSignature(
            component: component,
            operation: operation,
            configuration: configuration,
            labels: labels
        )
        let availableMethods = Self.availableMethods(
            operation: operation,
            configuredMethods: configuration.allowedMethods
        )
        self.selectedMethod = availableMethods.contains(configuration.defaultMethod)
            ? configuration.defaultMethod
            : availableMethods[0]
    }

    func update(
        component: PayabliPayIn,
        operation: PayabliPayInOperation,
        configuration: PayabliPayInFormConfiguration,
        labels: PayabliPayInFormLabels
    ) {
        let nextSignature = Self.lifecycleSignature(
            component: component,
            operation: operation,
            configuration: configuration,
            labels: labels
        )
        // The operation is what a submission sends, so it is taken even when nothing drawn changes.
        self.operation = operation
        guard nextSignature != lifecycleSignature else { return }

        objectWillChange.send()
        // A new component is a new payment flow, so the last flow's refusal describes nothing on it.
        let replacesFlow = component !== self.component
        // Before the swap: a combining-mark separator cannot be stripped back to digits.
        let expiry = submittedExpiration
        // By scalar, as the expiry is read: two spellings of one separator compare equal as strings.
        let separatorChanges = !configuration.formatting.expirationSeparator.unicodeScalars
            .elementsEqual(self.configuration.formatting.expirationSeparator.unicodeScalars)
        self.component = component
        self.configuration = configuration
        self.labels = labels
        if separatorChanges, !cardExpiration.isEmpty {
            cardExpiration = formatExpiration(expiry)
        }
        lifecycleSignature = nextSignature
        if replacesFlow {
            clearMarks()
        }
        // The opt-out applies to a message already drawn, so an update that withdraws it takes the
        // message with it; the marks stay, because a marked field is the whole answer. A message
        // still drawn follows the wording the form holds now, so a change to its label redraws it.
        if !configuration.showsFailureMessage {
            failureMessage = nil
            drawnFailure = nil
        } else if let failure = drawnFailure {
            failureMessage = PayabliPayInFailureMessage.text(
                for: failure.category,
                operation: failure.operation,
                labels: labels
            )
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

        guard case .storePaymentMethod = operation else { return fields }
        return fields.filter { field in
            field != .amount && field != .serviceFee && field != .surchargeFee
        }
    }

    var detectedCardBrand: PayabliPayInCardBrand {
        PayabliPayInCardBrand.detect(cardNumber: cardNumber)
    }

    var availableMethods: [PayabliPayInMethodType] {
        Self.availableMethods(
            operation: operation,
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
                && submittedExpiration.payabliCaptureDigitsOnly.count >= 4
                && fieldHasRequiredValue(.cardSecurityCode)
                && fieldHasRequiredValue(.cardPostalCode)
                && requiredFieldsAreSatisfied
        case .bankAccount:
            return fieldHasRequiredValue(.accountHolder)
                && fieldHasRequiredValue(.routingNumber)
                && fieldHasRequiredValue(.accountNumber)
                && requiredFieldsAreSatisfied
        }
    }

    func submit() async throws -> PayabliPayInResult {
        failureMessage = nil
        drawnFailure = nil
        clearMarks()
        guard !isSubmitting else {
            let error = PayabliPayInError.AlreadySubmitting()
            component.reportFormRefusal(error, method: effectiveSelectedMethod, operation: operation.kind)
            drawFailureMessage(for: error, operation: operation.kind)
            throw error
        }
        isSubmitting = true
        // The operation sent, which picks the message even if the form is given another while it runs.
        let operation = self.operation
        submittingOperation = operation.kind
        defer {
            isSubmitting = false
            submittingOperation = nil
        }
        let submittedFlow = component

        // A missing field never becomes a submission, so nothing the payer typed is cleared.
        do {
            try validateRequiredFields()
        } catch {
            component.reportFormRefusal(error, method: effectiveSelectedMethod, operation: operation.kind)
            drawFailureMessage(for: error, operation: operation.kind)
            throw error
        }

        let sendMark = PayabliSendMark()
        do {
            let result = try await PayabliSendMark.$current.withValue(sendMark) { try await submitToFlow(operation) }
            clearSensitiveFields()
            return result
        } catch {
            // The card and bank fields go only once the service may have acted on them, whatever the error. A 401
            // that is not resent left nothing the service acted on, so the payer's entry stays.
            if sendMark.mayHaveLeft {
                clearSensitiveFieldsAfterFailure()
            }
            // After the clear, because its edits take a mark off. A refusal of a flow replaced while
            // it was in flight marks nothing.
            if component === submittedFlow {
                rejectedFields = PayabliPayInRejectedFields.fields(in: error).intersection(activeFields)
            }
            // A marked field is the whole answer; a failure that marks none on screen shows its
            // message, which the opt-out hides while the marks stay.
            drawFailureMessage(for: error, operation: operation.kind)
            throw error
        }
    }

    /// Draws the failure's message where the form shows one, or takes it away, remembering the
    /// category and operation that picked the wording so a change to the wording redraws the
    /// message already drawn.
    private func drawFailureMessage(for error: any Error, operation: PayabliPayInOperation.Kind) {
        guard rejectedFields.isEmpty, configuration.showsFailureMessage else {
            failureMessage = nil
            drawnFailure = nil
            return
        }
        let category = PayabliPayInFailureMessage.messageCategory(for: error)
        drawnFailure = (category, operation)
        failureMessage = PayabliPayInFailureMessage.text(for: category, operation: operation, labels: labels)
    }

    /// Hands the form's submission to the flow, which reports it. A refusal before the flow has it is reported here.
    ///
    /// The submission runs inside `withFormBuffers`, so the buffers it built are closed once it ends,
    /// whatever it ends in.
    ///
    /// - Parameter operation: the operation the submission sends.
    /// - Returns: what the flow returned.
    private func submitToFlow(_ operation: PayabliPayInOperation) async throws -> PayabliPayInResult {
        try await withFormBuffers { buffers in
            let request: PayabliPayInRequest?
            do {
                request = try configuredRequest(for: operation, with: buffers)
            } catch {
                component.reportFormRefusal(error, method: effectiveSelectedMethod, operation: operation.kind)
                throw error
            }
            if let request {
                return try await component.submitConfigured(request, for: operation, origin: .form)
            }
            return try await component.submitConfigured(
                PayabliPayInStoreRequest(instrument: methodInput(with: buffers), options: mergedStoreOptions()),
                for: operation,
                origin: .form
            )
        }
    }

    /// The payment the form submits, or nil when the operation stores a method instead.
    ///
    /// - Parameter operation: the operation whose configuration the request is built from.
    /// - Parameter buffers: the registry the submission's sensitive buffers are built through.
    /// - Returns: the request built from the configuration and the fields.
    private func configuredRequest(
        for operation: PayabliPayInOperation,
        with buffers: FormBufferRegistry
    ) throws -> PayabliPayInRequest? {
        guard let requestConfiguration = operation.requestConfiguration else { return nil }
        return requestConfiguration.request(
            paymentMethod: paymentMethod(with: buffers),
            customerData: mergedCustomerData()
        )
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

    /// The years the expiry picker offers: the current year, held to 2000 to 2099, and the 20 after it, up to 2099.
    ///
    /// - Parameter now: the moment read as the current year.
    /// - Returns: the years, earliest first.
    func expirationYearChoices(now: Date = Date()) -> [Int] {
        let first = PayabliPayInCardData.currentExpiryMonth(at: now).year
        return Array(first ... min(first + 20, PayabliPayInCardData.expiryYears.upperBound))
    }

    func ensureExpirationSelection(defaultDate: Date = Date()) {
        let current = PayabliPayInCardData.currentExpiryMonth(at: defaultDate)
        if cardExpirationMonth == nil {
            cardExpirationMonth = selectedExpirationMonth ?? current.month
        }
        if cardExpirationYear == nil {
            cardExpirationYear = selectedExpirationYear ?? current.year
        }
        synchronizeExpirationText()
    }

    func paymentSummaryLabelText(for field: PayabliPayInField) -> String {
        PayabliPayInSummaryRows.labelText(
            for: field,
            labels: labels
        )
    }

    private var validation: PayabliPayInValidation {
        operation.requestConfiguration?.validation ?? operation.storeOptions?.validation ?? .default
    }

    private static func availableMethods(
        operation: PayabliPayInOperation,
        configuredMethods: [PayabliPayInMethodType]
    ) -> [PayabliPayInMethodType] {
        let methods = configuredMethods.filter { method in
            switch operation.kind {
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
        operation: PayabliPayInOperation,
        configuration: PayabliPayInFormConfiguration,
        labels: PayabliPayInFormLabels
    ) -> String {
        payabliFramedSignature([
            "component:\(ObjectIdentifier(component))",
            "operation:\(operation.payabliViewModelSignature)",
            "configuration:\(configuration.payabliViewModelSignature)",
            "labels:\(labels.payabliViewModelSignature)"
        ])
    }

    private var selectedExpirationMonth: Int? {
        if let cardExpirationMonth {
            return cardExpirationMonth
        }
        let digits = submittedExpiration.payabliCaptureDigitsOnly
        guard digits.count >= 2 else { return nil }
        let monthText = String(digits.prefix(2))
        guard let month = Int(monthText), (1 ... 12).contains(month) else { return nil }
        return month
    }

    private var selectedExpirationYear: Int? {
        if let cardExpirationYear {
            return cardExpirationYear
        }
        let digits = submittedExpiration.payabliCaptureDigitsOnly
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

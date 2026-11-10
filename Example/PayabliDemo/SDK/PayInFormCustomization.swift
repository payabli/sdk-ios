import PayabliSDKPayIn
import SwiftUI

/// The settings the Simple Capture tab lets a viewer change, and what each one hands the SDK's form.
///
/// A preset sets every field at once. Each field can then be changed on its own.
struct PayInFormCustomization: Hashable {
    /// Names this tab on every request it sends, a capture and a save alike.
    static let source = "ios-simple-capture"
    /// What a method stored from this screen is sent with.
    static var storeOptions: PayabliPayInStoreOptions {
        PayabliPayInStoreOptions(
            forceCustomerCreation: true,
            // A capture or an authorization names its customer on the request instead.
            customerData: PayInDemoCustomer.customerData,
            methodDescription: QAIdentity.current.note("simple-save"),
            source: source
        )
    }

    enum Preset: String, CaseIterable, Identifiable {
        case sdkDefault = "Default"
        case brand = "Brand"
        case minimal = "Minimal"

        var id: String {
            rawValue
        }
    }

    /// The form's style alone: colours, fonts, inputs and the submit button.
    enum Look: String, CaseIterable, Identifiable {
        case sdkDefault = "SDK default"
        case brand = "Brand"
        case compact = "Compact"

        var id: String {
            rawValue
        }
    }

    enum Methods: String, CaseIterable, Identifiable {
        case cardAndBank = "Card and bank"
        case cardOnly = "Card only"
        case bankOnly = "Bank only"

        var id: String {
            rawValue
        }
    }

    enum InputSizing: String, CaseIterable, Identifiable {
        case standard = "Standard"
        case compact = "Compact"
        case large = "Large"

        var id: String {
            rawValue
        }
    }

    var look: Look = .sdkDefault
    var methods: Methods = .cardAndBank
    var startOn: PayabliPayInMethodType = .card
    var labelsInsideFields = false
    var hidesLabels = false
    var usesCustomWording = false
    var showsCustomerSection = false
    var customerSectionFirst = false
    var requiresCustomerNumber = false
    var groupsCardNumber = true
    var dashesExpiry = false
    var masksAccountNumber = true
    var fixesHolderType = false
    var cardBrandIconPlacement: PayabliPayInCardBrandIconPlacement = .trailing
    var failureMessagePlacement: PayabliPayInFailureMessagePlacement = .aboveSubmitButton
    var inputSizing: InputSizing = .standard

    init() {}

    init(preset: Preset) {
        switch preset {
        case .sdkDefault:
            break
        case .brand:
            look = .brand
            labelsInsideFields = true
            usesCustomWording = true
            fixesHolderType = true
            showsCustomerSection = true
            customerSectionFirst = true
            requiresCustomerNumber = true
            dashesExpiry = true
            cardBrandIconPlacement = .trailing
            failureMessagePlacement = .top
            inputSizing = .large
        case .minimal:
            look = .compact
            methods = .cardOnly
            hidesLabels = true
            fixesHolderType = true
            groupsCardNumber = false
            cardBrandIconPlacement = .hidden
            failureMessagePlacement = .aboveSubmitButton
            inputSizing = .compact
        }
    }

    /// The preset these settings equal, if any.
    var activePreset: Preset? {
        Preset.allCases.first { PayInFormCustomization(preset: $0) == self }
    }

    // MARK: - What the SDK is handed

    /// The form's configuration for `operation`.
    ///
    /// - Parameter operation: what the form is for.
    /// - Parameter held: the method of a payment whose retry is open. The form offers only that method, so it
    ///   draws no selector and the total stays the one the retry sends. A save sends no retry and ignores it.
    /// - Returns: the configuration to hand the form.
    func configuration(
        for operation: PayInOperation,
        holding held: PayabliPayInMethodType? = nil
    ) -> PayabliPayInFormConfiguration {
        // An authorization holds funds on a card and nothing else.
        let offered: [PayabliPayInMethodType] = operation == .authorize ? [.card] : allowedMethods
        let methods = operation == .storedMethod ? offered : held.map { [$0] } ?? offered
        return PayabliPayInFormConfiguration(
            allowedMethods: methods,
            defaultMethod: methods.count > 1 ? startOn : methods[0],
            cardSections: sections(paymentFields: Self.cardFields, sectionTitle: "Your card"),
            bankSections: sections(paymentFields: bankFields, sectionTitle: "Your bank"),
            labelLayout: labelsInsideFields ? .placeholder : .external,
            showsFieldLabels: !hidesLabels,
            formatting: PayabliPayInFormatting(
                insertsCardNumberSpaces: groupsCardNumber,
                expirationSeparator: dashesExpiry ? "-" : "/",
                masksAccountNumber: masksAccountNumber
            ),
            inputSizing: sdkInputSizing,
            cardBrandIconPlacement: cardBrandIconPlacement,
            failureMessagePlacement: failureMessagePlacement,
            requiredFields: requiresCustomerNumber ? [.customerNumber] : [],
            paymentSummary: paymentSummary,
            accountHolderType: fixesHolderType ? .personal : nil
        )
    }

    var style: PayabliPayInFormStyle {
        switch look {
        case .sdkDefault:
            .default
        case .brand:
            PayabliPayInFormStyle(
                accentColor: Self.brandColor,
                title: PayabliPayInTextStyle(
                    font: .system(.title2, design: .rounded).weight(.bold),
                    color: Self.brandColor
                ),
                subtitle: PayabliPayInTextStyle(
                    font: .system(.subheadline, design: .rounded),
                    color: .secondary
                ),
                sectionTitle: PayabliPayInTextStyle(
                    font: .system(.headline, design: .rounded),
                    color: Self.brandColor
                ),
                input: PayabliPayInInputStyle(
                    font: .system(.body, design: .rounded),
                    uiFont: UIFont.systemFont(ofSize: 17, weight: .medium),
                    textColor: Self.brandColor,
                    backgroundColor: Self.brandColor.opacity(0.06),
                    borderColor: Self.brandColor.opacity(0.35),
                    focusedBorderColor: Self.brandColor,
                    borderWidth: 1.5,
                    focusedBorderWidth: 2,
                    cornerRadius: 16,
                    pickerIconColor: Self.brandColor
                ),
                submitButton: PayabliPayInSubmitButtonStyle(
                    font: .system(.headline, design: .rounded),
                    backgroundColor: Self.brandColor,
                    cornerRadius: 26,
                    height: 56
                ),
                layout: PayabliPayInLayoutStyle(
                    contentSpacing: 24,
                    fieldGroupSpacing: 14,
                    sectionSpacing: 26
                )
            )
        case .compact:
            PayabliPayInFormStyle(
                accentColor: .primary,
                title: PayabliPayInTextStyle(font: .headline, color: .primary),
                input: PayabliPayInInputStyle(
                    backgroundColor: .clear,
                    borderColor: Color(uiColor: .separator),
                    cornerRadius: 0
                ),
                submitButton: PayabliPayInSubmitButtonStyle(
                    backgroundColor: .primary,
                    foregroundColor: Color(uiColor: .systemBackground),
                    cornerRadius: 0,
                    height: 44
                ),
                layout: PayabliPayInLayoutStyle(
                    contentSpacing: 12,
                    fieldGroupSpacing: 8,
                    pairedFieldSpacing: 8,
                    sectionSpacing: 12
                )
            )
        }
    }

    // MARK: -

    private static let brandColor = Color(red: 0.36, green: 0.18, blue: 0.62)

    private static let cardFields: [PayabliPayInField] = [
        .cardholderName, .cardNumber, .cardExpiration, .cardSecurityCode, .cardPostalCode
    ]

    /// A holder type the configuration supplies takes the place of its picker.
    private var bankFields: [PayabliPayInField] {
        let fields = PayabliPayInFormConfiguration.defaultBankFieldOrder
        return fixesHolderType ? fields.filter { $0 != .accountHolderType } : fields
    }

    private var customerFields: [PayabliPayInField] {
        [.firstName, .lastName] + (requiresCustomerNumber ? [.customerNumber] : []) + [.billingEmail]
    }

    private var allowedMethods: [PayabliPayInMethodType] {
        switch methods {
        case .cardAndBank: [.card, .bankAccount]
        case .cardOnly: [.card]
        case .bankOnly: [.bankAccount]
        }
    }

    /// The SDK always adds the amount rows to a capture, so an untitled section is as far as they go.
    private func sections(
        paymentFields: [PayabliPayInField],
        sectionTitle: String
    ) -> [PayabliPayInFieldSection] {
        let titled = usesCustomWording
        let payment = PayabliPayInFieldSection(
            title: titled ? sectionTitle : nil,
            fields: paymentFields
        )
        let customer = PayabliPayInFieldSection(
            title: titled ? "About you" : nil,
            fields: customerFields
        )
        let summary = PayabliPayInFieldSection(
            id: "summary",
            title: titled ? "Order total" : nil,
            fields: [.amount, .serviceFee],
            style: .summary
        )

        let entry = switch (showsCustomerSection, customerSectionFirst) {
        case (false, _): [payment]
        case (true, true): [customer, payment]
        case (true, false): [payment, customer]
        }
        return entry + [summary]
    }

    /// The wording the form draws for one operation: the wording the preset chose, or the
    /// SDK's own where a preset leaves it alone.
    func labels(for operation: PayInOperation) -> PayabliPayInFormLabels {
        let fieldLabels = usesCustomWording
            ? PayabliPayInFormLabels.defaultFieldLabels.merging(Self.brandFieldLabels) { _, brand in brand }
            : PayabliPayInFormLabels.defaultFieldLabels
        // With labels hidden, the placeholder is the only text a field has.
        let placeholders = hidesLabels ? Self.hiddenLabelPlaceholders : [:]

        guard usesCustomWording else {
            return PayabliPayInFormLabels(fieldLabels: fieldLabels, fieldPlaceholders: placeholders)
        }
        return PayabliPayInFormLabels(
            title: "Acme Checkout",
            subtitle: "Secure payment, powered by Payabli",
            submitButton: Self.customSubmitWording(for: operation),
            fieldLabels: fieldLabels,
            fieldPlaceholders: placeholders
        )
    }

    private static func customSubmitWording(for operation: PayInOperation) -> String {
        switch operation {
        case .capture, .void: "Pay now"
        case .authorize: "Place hold"
        case .storedMethod: "Save for later"
        }
    }

    private static let brandFieldLabels: [PayabliPayInField: String] = [
        .cardholderName: "Name on card",
        .cardNumber: "Card",
        .cardExpiration: "Expires",
        .cardSecurityCode: "Security code",
        .cardPostalCode: "Billing ZIP",
        .accountHolder: "Name on account",
        .routingNumber: "Bank routing",
        .accountNumber: "Bank account",
        .firstName: "Given name",
        .lastName: "Family name",
        .customerNumber: "Member ID",
        .billingEmail: "Receipt email"
    ]

    private static let hiddenLabelPlaceholders: [PayabliPayInField: String] = [
        .cardholderName: "Name on card",
        .cardNumber: "Card number",
        .cardSecurityCode: "CVV",
        .cardPostalCode: "ZIP",
        .accountHolder: "Account holder",
        .routingNumber: "Routing number",
        .accountNumber: "Account number",
        .firstName: "First name",
        .lastName: "Last name",
        .customerNumber: "Customer number",
        .billingEmail: "Email"
    ]

    private var sdkInputSizing: PayabliPayInInputSizing {
        switch inputSizing {
        case .standard:
            PayabliPayInInputSizing()
        case .compact:
            PayabliPayInInputSizing(
                defaultSize: PayabliPayInInputSize(height: 44, horizontalPadding: 8)
            )
        case .large:
            PayabliPayInInputSizing(
                defaultSize: PayabliPayInInputSize(height: 60, horizontalPadding: 18)
            )
        }
    }

    private var paymentSummary: PayabliPayInPaymentSummaryConfiguration {
        switch look {
        case .brand:
            PayabliPayInPaymentSummaryConfiguration(
                labelStyle: PayabliPayInPaymentSummaryTextStyle(
                    font: .system(.subheadline, design: .rounded),
                    color: .secondary
                ),
                valueStyle: PayabliPayInPaymentSummaryTextStyle(
                    font: .system(.headline, design: .rounded),
                    color: Self.brandColor
                ),
                rowSpacing: 10
            )
        case .sdkDefault, .compact:
            PayabliPayInPaymentSummaryConfiguration()
        }
    }
}

/// The method on the form a screen shows, which is the method a charge from it is sent with.
///
/// Set when a form is built and when it reports a move. A configuration handed to a form already built moves
/// the method only through that report, so it is never worked out again from the latest configuration.
struct ShownFormMethod: Equatable {
    private(set) var method: PayabliPayInMethodType?

    /// A form was built, and opens on its configuration's default without reporting it.
    ///
    /// - Parameter configuration: the configuration the form was built with.
    mutating func formBuilt(with configuration: PayabliPayInFormConfiguration) {
        method = configuration.defaultMethod
    }

    /// The form reported drawing `method`.
    ///
    /// - Parameter method: the method it moved to.
    mutating func moved(to method: PayabliPayInMethodType) {
        self.method = method
    }

    /// The method an open retry must send once a charge from this form has failed.
    ///
    /// - Parameter failure: how the charge ended.
    /// - Parameter held: the method held before it, if a retry was open.
    /// - Returns: the method sent while the outcome is unknown, nil once the service answered the payment, and
    ///   otherwise the one held.
    func heldMethod(after failure: PayInFailure, holding held: PayabliPayInMethodType?) -> PayabliPayInMethodType? {
        if failure.outcomeIsUnresolved {
            return method
        }
        return failure.answersThePayment ? nil : held
    }
}

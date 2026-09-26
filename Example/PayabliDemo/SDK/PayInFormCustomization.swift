import PayabliSDKPayIn
import SwiftUI

/// The settings the Simple Capture tab lets a viewer change, and what each one hands the SDK's form.
///
/// A preset sets every field at once. Each field can then be changed on its own.
struct PayInFormCustomization: Hashable {
    /// Names this tab on every request it sends, a capture and a save alike.
    static let source = "ios-simple-capture"

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
    var titlesAmountSummary = true
    var groupsCardNumber = true
    var dashesExpiry = false
    var masksAccountNumber = true
    var fixesHolderType = false
    var cardBrandIconPlacement: PayabliPayInCardBrandIconPlacement = .trailing
    var errorMessagePlacement: PayabliPayInErrorMessagePlacement = .aboveSubmitButton
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
            errorMessagePlacement = .top
            inputSizing = .large
        case .minimal:
            look = .compact
            methods = .cardOnly
            hidesLabels = true
            fixesHolderType = true
            titlesAmountSummary = false
            groupsCardNumber = false
            cardBrandIconPlacement = .hidden
            errorMessagePlacement = .aboveSubmitButton
            inputSizing = .compact
        }
    }

    /// The preset these settings equal, if any.
    var activePreset: Preset? {
        Preset.allCases.first { PayInFormCustomization(preset: $0) == self }
    }

    // MARK: - What the SDK is handed

    func configuration(capturing: Bool) -> PayabliPayInFormConfiguration {
        PayabliPayInFormConfiguration(
            allowedMethods: allowedMethods,
            defaultMethod: methods == .cardAndBank ? startOn : allowedMethods[0],
            cardSections: sections(paymentFields: Self.cardFields, sectionTitle: "Your card"),
            bankSections: sections(paymentFields: bankFields, sectionTitle: "Your bank"),
            hiddenValues: PayabliPayInHiddenValues(
                accountHolderType: fixesHolderType ? .personal : nil,
                methodDescription: QAIdentity.current.note(capturing ? "simple-capture" : "simple-save"),
                // A capture names its customer on the request instead.
                customerData: capturing ? nil : PayInDemoCustomer.customerData
            ),
            options: PayabliPayInOptions(forceCustomerCreation: true, source: Self.source),
            labels: labels(capturing: capturing),
            labelLayout: labelsInsideFields ? .placeholder : .external,
            showsFieldLabels: !hidesLabels,
            formatting: PayabliPayInFormatting(
                insertsCardNumberSpaces: groupsCardNumber,
                expirationSeparator: dashesExpiry ? "-" : "/",
                masksAccountNumber: masksAccountNumber
            ),
            inputSizing: sdkInputSizing,
            cardBrandIconPlacement: cardBrandIconPlacement,
            errorMessagePlacement: errorMessagePlacement,
            requiredFields: requiresCustomerNumber ? [.customerNumber] : [],
            paymentSummary: paymentSummary
        )
    }

    var style: PayabliPayInStyle {
        switch look {
        case .sdkDefault:
            .default
        case .brand:
            PayabliPayInStyle(
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
            PayabliPayInStyle(
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
        .cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip
    ]

    /// A holder type supplied as a hidden value takes the place of its picker.
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
            title: titlesAmountSummary ? (titled ? "Order total" : "Payment Information") : nil,
            fields: [.amount, .serviceFee]
        )

        let entry = switch (showsCustomerSection, customerSectionFirst) {
        case (false, _): [payment]
        case (true, true): [customer, payment]
        case (true, false): [payment, customer]
        }
        return entry + [summary]
    }

    private func labels(capturing: Bool) -> PayabliPayInLabels {
        let fieldLabels = usesCustomWording
            ? PayabliPayInLabels.defaultFieldLabels.merging(Self.brandFieldLabels) { _, brand in brand }
            : PayabliPayInLabels.defaultFieldLabels
        // With labels hidden, the placeholder is the only text a field has.
        let placeholders = hidesLabels ? Self.hiddenLabelPlaceholders : [:]

        guard usesCustomWording else {
            return PayabliPayInLabels(fieldLabels: fieldLabels, fieldPlaceholders: placeholders)
        }
        return PayabliPayInLabels(
            title: "Acme Checkout",
            subtitle: "Secure payment, powered by Payabli",
            submitButton: capturing ? "Pay now" : "Save for later",
            fieldLabels: fieldLabels,
            fieldPlaceholders: placeholders
        )
    }

    private static let brandFieldLabels: [PayabliPayInField: String] = [
        .cardholderName: "Name on card",
        .cardNumber: "Card",
        .cardExpiration: "Expires",
        .cardCvv: "Security code",
        .cardZip: "Billing ZIP",
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
        .cardCvv: "CVV",
        .cardZip: "ZIP",
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

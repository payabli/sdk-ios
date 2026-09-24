import PayabliSDKPayInPaymentFlow
import SwiftUI

/// The settings the Simple Capture tab lets a viewer change, and what each one hands the SDK's form.
///
/// A preset sets every field at once. Each field can then be changed on its own.
struct PayInFormCustomization: Hashable {
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
        case appTheme = "App theme"
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

    var look: Look = .appTheme
    var methods: Methods = .cardAndBank
    var startOn: PayabliPayInPaymentFlowMethodType = .card
    var labelsInsideFields = false
    var hidesLabels = false
    var usesCustomWording = false
    var showsCustomerSection = true
    var customerSectionFirst = false
    var requiresCustomerNumber = false
    var showsAmountSummary = true
    var groupsCardNumber = true
    var dashesExpiry = false
    var masksAccountNumber = true
    var cardBrandIconPlacement: PayabliPayInPaymentFlowCardBrandIconPlacement = .leading
    var errorMessagePlacement: PayabliPayInPaymentFlowErrorMessagePlacement = .top
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
            showsCustomerSection = false
            showsAmountSummary = false
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

    func configuration(capturing: Bool) -> PayabliPayInPaymentFlowFormConfiguration {
        PayabliPayInPaymentFlowFormConfiguration(
            allowedMethods: allowedMethods,
            defaultMethod: methods == .cardAndBank ? startOn : allowedMethods[0],
            cardSections: sections(paymentFields: Self.cardFields, sectionTitle: "Card"),
            achSections: sections(paymentFields: Self.bankFields, sectionTitle: "Bank account"),
            hiddenValues: PayabliPayInPaymentFlowHiddenValues(
                achHolderType: .personal,
                methodDescription: QAIdentity.current.note(capturing ? "simple-capture" : "simple-save"),
                // A capture names its customer on the request instead.
                customerData: capturing ? nil : PayInDemoCustomer.customerData
            ),
            options: PayabliPayInPaymentFlowOptions(forceCustomerCreation: true, source: "ios-simple-capture"),
            labels: labels(capturing: capturing),
            labelLayout: labelsInsideFields ? .placeholder : .external,
            showsFieldLabels: !hidesLabels,
            formatting: PayabliPayInPaymentFlowFormatting(
                insertsCardNumberSpaces: groupsCardNumber,
                expirationSeparator: dashesExpiry ? "-" : "/",
                masksACHAccountEntry: masksAccountNumber
            ),
            inputSizing: sdkInputSizing,
            cardBrandIconPlacement: cardBrandIconPlacement,
            errorMessagePlacement: errorMessagePlacement,
            requiredFields: requiresCustomerNumber ? [.customerNumber] : [],
            paymentSummary: paymentSummary
        )
    }

    var style: PayabliPayInPaymentFlowStyle {
        switch look {
        case .appTheme:
            PayInSharedConfiguration.style
        case .brand:
            PayabliPayInPaymentFlowStyle(
                accentColor: Self.brandColor,
                title: PayabliPayInPaymentFlowTextStyle(
                    font: .system(.title2, design: .rounded).weight(.bold),
                    color: Self.brandColor
                ),
                subtitle: PayabliPayInPaymentFlowTextStyle(
                    font: .system(.subheadline, design: .rounded),
                    color: .secondary
                ),
                sectionTitle: PayabliPayInPaymentFlowTextStyle(
                    font: .system(.headline, design: .rounded),
                    color: Self.brandColor
                ),
                input: PayabliPayInPaymentFlowInputStyle(
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
                submitButton: PayabliPayInPaymentFlowSubmitButtonStyle(
                    font: .system(.headline, design: .rounded),
                    backgroundColor: Self.brandColor,
                    cornerRadius: 26,
                    height: 56
                ),
                layout: PayabliPayInPaymentFlowLayoutStyle(
                    contentSpacing: 24,
                    fieldGroupSpacing: 14,
                    sectionSpacing: 26
                )
            )
        case .compact:
            PayabliPayInPaymentFlowStyle(
                accentColor: .primary,
                title: PayabliPayInPaymentFlowTextStyle(font: .headline, color: .primary),
                input: PayabliPayInPaymentFlowInputStyle(
                    backgroundColor: .clear,
                    borderColor: Color(uiColor: .separator),
                    cornerRadius: 0
                ),
                submitButton: PayabliPayInPaymentFlowSubmitButtonStyle(
                    backgroundColor: .primary,
                    foregroundColor: Color(uiColor: .systemBackground),
                    cornerRadius: 0,
                    height: 44
                ),
                layout: PayabliPayInPaymentFlowLayoutStyle(
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

    private static let cardFields: [PayabliPayInPaymentFlowField] = [
        .cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip
    ]

    private static let bankFields: [PayabliPayInPaymentFlowField] = [
        .achHolder, .achRouting, .achAccount, .achAccountType
    ]

    private var customerFields: [PayabliPayInPaymentFlowField] {
        [.firstName, .lastName] + (requiresCustomerNumber ? [.customerNumber] : []) + [.billingEmail]
    }

    private var allowedMethods: [PayabliPayInPaymentFlowMethodType] {
        switch methods {
        case .cardAndBank: [.card, .bankAccount]
        case .cardOnly: [.card]
        case .bankOnly: [.bankAccount]
        }
    }

    /// The SDK always adds the amount rows to a capture, so an untitled section is as far as they go.
    private func sections(
        paymentFields: [PayabliPayInPaymentFlowField],
        sectionTitle: String
    ) -> [PayabliPayInPaymentFlowFieldSection] {
        let titled = usesCustomWording
        let payment = PayabliPayInPaymentFlowFieldSection(
            title: titled ? sectionTitle : nil,
            fields: paymentFields
        )
        let customer = PayabliPayInPaymentFlowFieldSection(
            title: titled ? "Your details" : nil,
            fields: customerFields
        )
        let summary = PayabliPayInPaymentFlowFieldSection(
            id: "summary",
            title: showsAmountSummary ? (titled ? "Order summary" : "Payment Information") : nil,
            fields: [.amount, .serviceFee]
        )

        let entry = switch (showsCustomerSection, customerSectionFirst) {
        case (false, _): [payment]
        case (true, true): [customer, payment]
        case (true, false): [payment, customer]
        }
        return entry + [summary]
    }

    private func labels(capturing: Bool) -> PayabliPayInPaymentFlowLabels {
        let fieldLabels = usesCustomWording
            ? PayabliPayInPaymentFlowLabels.defaultFieldLabels.merging(Self.brandFieldLabels) { _, brand in brand }
            : PayabliPayInPaymentFlowLabels.defaultFieldLabels
        // With labels hidden and outside the fields, the placeholder is the only text a field has.
        let placeholders = hidesLabels && !labelsInsideFields ? fieldLabels : [:]

        guard usesCustomWording else {
            return PayabliPayInPaymentFlowLabels(fieldLabels: fieldLabels, fieldPlaceholders: placeholders)
        }
        return PayabliPayInPaymentFlowLabels(
            title: capturing ? "Checkout" : "Save a card for later",
            subtitle: "Secure payment powered by Payabli",
            submitButton: capturing ? "Pay now" : "Save securely",
            fieldLabels: fieldLabels,
            fieldPlaceholders: placeholders
        )
    }

    private static let brandFieldLabels: [PayabliPayInPaymentFlowField: String] = [
        .cardholderName: "Cardholder",
        .cardNumber: "Card",
        .cardExpiration: "Expires",
        .cardCvv: "Security code",
        .cardZip: "ZIP",
        .achHolder: "Name on account",
        .firstName: "First",
        .lastName: "Last",
        .customerNumber: "Member number",
        .billingEmail: "Email for receipt",
        .amount: "Subtotal",
        .serviceFee: "Processing fee"
    ]

    private var sdkInputSizing: PayabliPayInPaymentFlowInputSizing {
        switch inputSizing {
        case .standard:
            PayabliPayInPaymentFlowInputSizing()
        case .compact:
            PayabliPayInPaymentFlowInputSizing(
                defaultSize: PayabliPayInPaymentFlowInputSize(height: 44, horizontalPadding: 8)
            )
        case .large:
            PayabliPayInPaymentFlowInputSizing(
                defaultSize: PayabliPayInPaymentFlowInputSize(height: 60, horizontalPadding: 18)
            )
        }
    }

    private var paymentSummary: PayabliPayInPaymentFlowPaymentSummaryConfiguration {
        switch look {
        case .brand:
            PayabliPayInPaymentFlowPaymentSummaryConfiguration(
                labelStyle: PayabliPayInPaymentFlowPaymentSummaryTextStyle(
                    font: .system(.subheadline, design: .rounded),
                    color: .secondary
                ),
                valueStyle: PayabliPayInPaymentFlowPaymentSummaryTextStyle(
                    font: .system(.headline, design: .rounded),
                    color: Self.brandColor
                ),
                rowSpacing: 10
            )
        case .appTheme, .compact:
            PayabliPayInPaymentFlowPaymentSummaryConfiguration()
        }
    }
}

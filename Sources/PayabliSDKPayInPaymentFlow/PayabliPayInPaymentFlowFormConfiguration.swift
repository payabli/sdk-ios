import Foundation
import SwiftUI

public enum PayabliPayInPaymentFlowField: String, CaseIterable, Identifiable, Sendable {
    case cardholderName
    case cardNumber
    case cardExpiration
    case cardCvv
    case cardZip
    case accountHolder
    case routingNumber
    case accountNumber
    case accountType
    case accountHolderType
    case secCode
    case deviceId
    case methodDescription
    case firstName
    case lastName
    case customerNumber
    case billingEmail
    case billingZip
    case amount
    case serviceFee

    public var id: String {
        rawValue
    }
}

public enum PayabliPayInPaymentFlowLabelLayout: Sendable {
    case external
    case placeholder
}

// Public API keeps the PayInPaymentFlow namespace for discoverability.
// swiftlint:disable:next type_name
public enum PayabliPayInPaymentFlowCardBrandIconPlacement: Sendable, Equatable {
    case leading
    case trailing
    case hidden
}

// Public API keeps the PayInPaymentFlow namespace for discoverability.
// swiftlint:disable:next type_name
public enum PayabliPayInPaymentFlowErrorMessagePlacement: Sendable, Equatable {
    case top
    case aboveSubmitButton
}

public struct PayabliPayInPaymentFlowFormatting: Sendable {
    public let insertsCardNumberSpaces: Bool
    public let expirationSeparator: String
    public let masksAccountNumber: Bool

    public init(
        insertsCardNumberSpaces: Bool = true,
        expirationSeparator: String = "/",
        masksAccountNumber: Bool = true
    ) {
        self.insertsCardNumberSpaces = insertsCardNumberSpaces
        self.expirationSeparator = expirationSeparator.isEmpty ? "/" : expirationSeparator
        self.masksAccountNumber = masksAccountNumber
    }
}

public struct PayabliPayInPaymentFlowHiddenValues: Sendable {
    public let accountHolderType: PayabliPayInAccountHolderType?
    public let secCode: PayabliPayInSecCode?
    public let deviceId: String?
    public let methodDescription: String?
    public let customerData: PayabliPayInPaymentFlowCustomerData?

    public init(
        accountHolderType: PayabliPayInAccountHolderType? = nil,
        secCode: PayabliPayInSecCode? = .web,
        deviceId: String? = nil,
        methodDescription: String? = nil,
        customerData: PayabliPayInPaymentFlowCustomerData? = nil
    ) {
        self.accountHolderType = accountHolderType
        self.secCode = secCode
        self.deviceId = deviceId
        self.methodDescription = methodDescription
        self.customerData = customerData
    }
}

public typealias PayabliPayInPaymentFlowOptions = PayabliPayInPaymentFlowTokenStorageOptions

public struct PayabliPayInPaymentFlowInputSize: Sendable, Equatable {
    public let width: CGFloat?
    public let height: CGFloat
    public let horizontalPadding: CGFloat

    public init(
        width: CGFloat? = nil,
        height: CGFloat = 52,
        horizontalPadding: CGFloat = 14
    ) {
        self.width = width
        self.height = max(PayabliPayInPaymentFlowAccessibility.minimumTouchTarget, height)
        self.horizontalPadding = max(0, horizontalPadding)
    }
}

public struct PayabliPayInPaymentFlowLabels: Sendable {
    public let title: String
    public let subtitle: String?
    public let submitButton: String
    public let fieldLabels: [PayabliPayInPaymentFlowField: String]
    public let fieldPlaceholders: [PayabliPayInPaymentFlowField: String]

    public init(
        title: String = "Save Payment Method",
        subtitle: String? = nil,
        submitButton: String = "Add Payment Method",
        fieldLabels: [PayabliPayInPaymentFlowField: String] = Self.defaultFieldLabels,
        fieldPlaceholders: [PayabliPayInPaymentFlowField: String] = [:]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.submitButton = submitButton
        self.fieldLabels = fieldLabels
        self.fieldPlaceholders = fieldPlaceholders
    }

    public func label(for field: PayabliPayInPaymentFlowField) -> String {
        fieldLabels[field] ?? Self.defaultFieldLabels[field] ?? field.rawValue
    }

    public func placeholder(for field: PayabliPayInPaymentFlowField) -> String? {
        fieldPlaceholders[field]?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
    }

    public static let defaultFieldLabels: [PayabliPayInPaymentFlowField: String] = [
        .cardholderName: "Name on card",
        .cardNumber: "Card number",
        .cardExpiration: "Expiration",
        .cardCvv: "CVV",
        .cardZip: "Postal Code",
        .accountHolder: "Account holder",
        .routingNumber: "Routing number",
        .accountNumber: "Account number",
        .accountType: "Account type",
        .accountHolderType: "Holder type",
        .secCode: "SEC code",
        .deviceId: "Device",
        .methodDescription: "Description",
        .firstName: "First name",
        .lastName: "Last name",
        .customerNumber: "Customer number",
        .billingEmail: "Billing email",
        .billingZip: "Billing Postal Code",
        .amount: "Amount",
        .serviceFee: "Fee"
    ]
}

public struct PayabliPayInPaymentFlowFieldSection: Identifiable, Sendable {
    public let id: String
    public let title: String?
    public let titleStyle: PayabliPayInPaymentFlowTextStyle?
    public let fields: [PayabliPayInPaymentFlowField]
    public let inputVerticalSpacing: CGFloat?
    public let inputHorizontalSpacing: CGFloat?
    public let fieldVerticalSpacings: [PayabliPayInPaymentFlowField: CGFloat]

    public init(
        id: String? = nil,
        title: String? = nil,
        titleStyle: PayabliPayInPaymentFlowTextStyle? = nil,
        fields: [PayabliPayInPaymentFlowField],
        inputVerticalSpacing: CGFloat? = nil,
        inputHorizontalSpacing: CGFloat? = nil,
        fieldVerticalSpacings: [PayabliPayInPaymentFlowField: CGFloat] = [:]
    ) {
        let resolvedTitle = title?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
        self.id = id?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
            ?? resolvedTitle
            ?? fields.map(\.rawValue).joined(separator: "-")
        self.title = resolvedTitle
        self.titleStyle = titleStyle
        self.fields = fields
        self.inputVerticalSpacing = inputVerticalSpacing.map { max(0, $0) }
        self.inputHorizontalSpacing = inputHorizontalSpacing.map { max(0, $0) }
        self.fieldVerticalSpacings = fieldVerticalSpacings.mapValues { max(0, $0) }
    }

    func replacingFields(_ fields: [PayabliPayInPaymentFlowField]) -> PayabliPayInPaymentFlowFieldSection {
        PayabliPayInPaymentFlowFieldSection(
            id: id,
            title: title,
            titleStyle: titleStyle,
            fields: fields,
            inputVerticalSpacing: inputVerticalSpacing,
            inputHorizontalSpacing: inputHorizontalSpacing,
            fieldVerticalSpacings: fieldVerticalSpacings
        )
    }
}

public struct PayabliPayInPaymentFlowInputSizing: Sendable, Equatable {
    public let defaultSize: PayabliPayInPaymentFlowInputSize
    public let fieldSizes: [PayabliPayInPaymentFlowField: PayabliPayInPaymentFlowInputSize]

    public init(
        defaultSize: PayabliPayInPaymentFlowInputSize = PayabliPayInPaymentFlowInputSize(),
        fieldSizes: [PayabliPayInPaymentFlowField: PayabliPayInPaymentFlowInputSize] = [:]
    ) {
        self.defaultSize = defaultSize
        self.fieldSizes = fieldSizes
    }

    public func size(for field: PayabliPayInPaymentFlowField) -> PayabliPayInPaymentFlowInputSize {
        fieldSizes[field] ?? defaultSize
    }
}

// Public API keeps the PayInPaymentFlow namespace for discoverability.
// swiftlint:disable:next type_name
public struct PayabliPayInPaymentFlowPaymentSummaryTextStyle: Sendable {
    public let font: Font
    public let color: Color

    public init(
        font: Font = .body,
        color: Color = .primary
    ) {
        self.font = font
        self.color = color
    }
}

// Public API keeps the PayInPaymentFlow namespace for discoverability.
// swiftlint:disable:next type_name
public struct PayabliPayInPaymentFlowPaymentSummaryConfiguration: Sendable {
    public let amountLabelText: String?
    public let amountValueText: String?
    public let feeLabelText: String?
    public let feeValueText: String?
    public let currencySymbol: String
    public let labelStyle: PayabliPayInPaymentFlowPaymentSummaryTextStyle
    public let valueStyle: PayabliPayInPaymentFlowPaymentSummaryTextStyle
    public let rowSpacing: CGFloat

    public init(
        amountLabelText: String? = nil,
        amountValueText: String? = nil,
        feeLabelText: String? = nil,
        feeValueText: String? = nil,
        currencySymbol: String = "$",
        labelStyle: PayabliPayInPaymentFlowPaymentSummaryTextStyle = PayabliPayInPaymentFlowPaymentSummaryTextStyle(
            font: .subheadline,
            color: .secondary
        ),
        valueStyle: PayabliPayInPaymentFlowPaymentSummaryTextStyle = PayabliPayInPaymentFlowPaymentSummaryTextStyle(
            font: .subheadline.weight(.semibold),
            color: .primary
        ),
        rowSpacing: CGFloat = 8
    ) {
        self.amountLabelText = amountLabelText?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
        self.amountValueText = amountValueText?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
        self.feeLabelText = feeLabelText?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
        self.feeValueText = feeValueText?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
        self.currencySymbol = currencySymbol.payabliCaptureTrimmed.payabliCaptureNilIfEmpty ?? "$"
        self.labelStyle = labelStyle
        self.valueStyle = valueStyle
        self.rowSpacing = max(0, rowSpacing)
    }

    public func labelText(
        for field: PayabliPayInPaymentFlowField,
        labels: PayabliPayInPaymentFlowLabels
    ) -> String {
        switch field {
        case .amount:
            return amountLabelText ?? Self.defaultLabelText(label: labels.label(for: field))
        case .serviceFee:
            return feeLabelText ?? Self.defaultLabelText(label: labels.label(for: field))
        default:
            return labels.label(for: field)
        }
    }

    public func valueText(
        for field: PayabliPayInPaymentFlowField,
        paymentDetails: PayabliPayInPaymentFlowPaymentDetails?
    ) -> String {
        switch field {
        case .amount:
            return amountValueText ?? Self.defaultValueText(
                currencySymbol: currencySymbol,
                value: paymentDetails?.totalAmount ?? 0
            )
        case .serviceFee:
            return feeValueText ?? Self.defaultValueText(
                currencySymbol: currencySymbol,
                value: paymentDetails?.serviceFee ?? 0
            )
        default:
            return ""
        }
    }

    public func accessibilityText(
        for field: PayabliPayInPaymentFlowField,
        labels: PayabliPayInPaymentFlowLabels,
        paymentDetails: PayabliPayInPaymentFlowPaymentDetails?
    ) -> String {
        [
            labelText(for: field, labels: labels),
            valueText(for: field, paymentDetails: paymentDetails)
        ]
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }

    private static func defaultLabelText(label: String) -> String {
        "\(label):"
    }

    private static func defaultValueText(
        currencySymbol: String,
        value: Double
    ) -> String {
        "\(currencySymbol) \(String(format: "%.2f", value))"
    }
}

public struct PayabliPayInPaymentFlowFormConfiguration: Sendable {
    public let allowedMethods: [PayabliPayInPaymentFlowMethodType]
    public let defaultMethod: PayabliPayInPaymentFlowMethodType
    public let cardFieldOrder: [PayabliPayInPaymentFlowField]
    public let bankFieldOrder: [PayabliPayInPaymentFlowField]
    public let hiddenValues: PayabliPayInPaymentFlowHiddenValues
    public let options: PayabliPayInPaymentFlowOptions
    public let labels: PayabliPayInPaymentFlowLabels
    public let labelLayout: PayabliPayInPaymentFlowLabelLayout
    public let showsFieldLabels: Bool
    public let hiddenFieldLabels: Set<PayabliPayInPaymentFlowField>
    public let formatting: PayabliPayInPaymentFlowFormatting
    public let inputSizing: PayabliPayInPaymentFlowInputSizing
    public let cardBrandIconPlacement: PayabliPayInPaymentFlowCardBrandIconPlacement
    public let errorMessagePlacement: PayabliPayInPaymentFlowErrorMessagePlacement
    public let requiredFields: Set<PayabliPayInPaymentFlowField>
    public let cardSections: [PayabliPayInPaymentFlowFieldSection]
    public let bankSections: [PayabliPayInPaymentFlowFieldSection]
    public let paymentSummary: PayabliPayInPaymentFlowPaymentSummaryConfiguration

    public init(
        allowedMethods: [PayabliPayInPaymentFlowMethodType] = [.card, .bankAccount],
        defaultMethod: PayabliPayInPaymentFlowMethodType = .card,
        cardFieldOrder: [PayabliPayInPaymentFlowField] = Self.defaultCardFieldOrder,
        bankFieldOrder: [PayabliPayInPaymentFlowField] = Self.defaultBankFieldOrder,
        cardSections: [PayabliPayInPaymentFlowFieldSection]? = nil,
        bankSections: [PayabliPayInPaymentFlowFieldSection]? = nil,
        hiddenValues: PayabliPayInPaymentFlowHiddenValues = PayabliPayInPaymentFlowHiddenValues(),
        options: PayabliPayInPaymentFlowOptions = PayabliPayInPaymentFlowOptions(),
        labels: PayabliPayInPaymentFlowLabels = PayabliPayInPaymentFlowLabels(),
        labelLayout: PayabliPayInPaymentFlowLabelLayout = .external,
        showsFieldLabels: Bool? = nil,
        hiddenFieldLabels: Set<PayabliPayInPaymentFlowField> = [],
        formatting: PayabliPayInPaymentFlowFormatting = PayabliPayInPaymentFlowFormatting(),
        inputSizing: PayabliPayInPaymentFlowInputSizing = PayabliPayInPaymentFlowInputSizing(),
        cardBrandIconPlacement: PayabliPayInPaymentFlowCardBrandIconPlacement = .trailing,
        errorMessagePlacement: PayabliPayInPaymentFlowErrorMessagePlacement = .aboveSubmitButton,
        requiredFields: Set<PayabliPayInPaymentFlowField> = [],
        paymentSummary: PayabliPayInPaymentFlowPaymentSummaryConfiguration = PayabliPayInPaymentFlowPaymentSummaryConfiguration()
    ) {
        let methods = allowedMethods.isEmpty ? [defaultMethod] : allowedMethods
        let visibleRequiredFields = Self.visibleRequiredFields(from: requiredFields)
        let requiredCardFields = Self.requiredCardFields + Self.cardRequiredFields(from: visibleRequiredFields)
        let requiredBankFields = Self.requiredBankFields + Self.bankRequiredFields(from: visibleRequiredFields)
        let normalizedCardSections = Self.normalizedSections(
            cardSections,
            defaultSections: Self.defaultCardSections(cardFieldOrder: cardFieldOrder),
            required: requiredCardFields,
            appendedFields: Self.paymentDetailFields
        )
        let normalizedBankSections = Self.normalizedSections(
            bankSections,
            defaultSections: Self.defaultBankSections(bankFieldOrder: bankFieldOrder),
            required: requiredBankFields,
            appendedFields: Self.paymentDetailFields,
            hiddenFields: [.secCode]
        )
        self.allowedMethods = methods
        self.defaultMethod = methods.contains(defaultMethod) ? defaultMethod : methods[0]
        self.cardFieldOrder = normalizedCardSections.flatMap(\.fields)
        self.bankFieldOrder = normalizedBankSections.flatMap(\.fields)
        self.cardSections = normalizedCardSections
        self.bankSections = normalizedBankSections
        self.hiddenValues = hiddenValues
        self.options = options
        self.labels = labels
        self.labelLayout = labelLayout
        self.showsFieldLabels = showsFieldLabels ?? (labelLayout == .external)
        self.hiddenFieldLabels = hiddenFieldLabels
        self.formatting = formatting
        self.inputSizing = inputSizing
        self.cardBrandIconPlacement = cardBrandIconPlacement
        self.errorMessagePlacement = errorMessagePlacement
        self.requiredFields = visibleRequiredFields.union(Self.requiredPaymentFields)
        self.paymentSummary = paymentSummary
    }

    public static let defaultCardFieldOrder: [PayabliPayInPaymentFlowField] = [
        .cardholderName,
        .cardNumber,
        .cardExpiration,
        .cardCvv,
        .cardZip
    ]

    public static let defaultBankFieldOrder: [PayabliPayInPaymentFlowField] = [
        .accountHolder,
        .routingNumber,
        .accountNumber,
        .accountType,
        .accountHolderType
    ]

    private static let requiredCardFields: [PayabliPayInPaymentFlowField] = [
        .cardNumber,
        .cardExpiration,
        .cardholderName,
        .cardCvv,
        .cardZip,
        .amount
    ]

    private static let requiredBankFields: [PayabliPayInPaymentFlowField] = [
        .accountHolder,
        .routingNumber,
        .accountNumber,
        .accountType,
        .amount
    ]

    private static let requiredPaymentFields: Set<PayabliPayInPaymentFlowField> = [.amount]
    private static let paymentDetailFields: [PayabliPayInPaymentFlowField] = [.amount, .serviceFee]

    private static func defaultCardSections(
        cardFieldOrder: [PayabliPayInPaymentFlowField]
    ) -> [PayabliPayInPaymentFlowFieldSection] {
        [
            PayabliPayInPaymentFlowFieldSection(fields: cardFieldOrder),
            PayabliPayInPaymentFlowFieldSection(title: "Payment Information", fields: paymentDetailFields)
        ]
    }

    private static func defaultBankSections(
        bankFieldOrder: [PayabliPayInPaymentFlowField]
    ) -> [PayabliPayInPaymentFlowFieldSection] {
        [
            PayabliPayInPaymentFlowFieldSection(fields: visibleBankFields(from: bankFieldOrder)),
            PayabliPayInPaymentFlowFieldSection(title: "Payment Information", fields: paymentDetailFields)
        ]
    }

    private static func normalizedSections(
        _ sections: [PayabliPayInPaymentFlowFieldSection]?,
        defaultSections: [PayabliPayInPaymentFlowFieldSection],
        required: [PayabliPayInPaymentFlowField],
        appendedFields: [PayabliPayInPaymentFlowField],
        hiddenFields: Set<PayabliPayInPaymentFlowField> = []
    ) -> [PayabliPayInPaymentFlowFieldSection] {
        let sourceSections = sections?.isEmpty == false ? sections ?? [] : defaultSections
        var seenFields = Set<PayabliPayInPaymentFlowField>()
        var output = sourceSections.compactMap { section -> PayabliPayInPaymentFlowFieldSection? in
            let visibleFields = section.fields.filter { field in
                !hiddenFields.contains(field) && seenFields.insert(field).inserted
            }
            guard !visibleFields.isEmpty else { return nil }
            return section.replacingFields(visibleFields)
        }

        for field in required + appendedFields where !hiddenFields.contains(field) && !seenFields.contains(field) {
            append(field, to: &output)
            seenFields.insert(field)
        }

        return output
    }

    private static func append(
        _ field: PayabliPayInPaymentFlowField,
        to sections: inout [PayabliPayInPaymentFlowFieldSection]
    ) {
        guard !sections.isEmpty else {
            sections = [PayabliPayInPaymentFlowFieldSection(fields: [field])]
            return
        }

        if paymentDetailFields.contains(field),
           sections.contains(where: { section in section.fields.contains { paymentDetailFields.contains($0) } }) == false
        {
            sections.append(PayabliPayInPaymentFlowFieldSection(title: "Payment Information", fields: [field]))
            return
        }

        let targetIndex: Int = if paymentDetailFields.contains(field) {
            sections.lastIndex { section in
                section.fields.contains { paymentDetailFields.contains($0) }
            } ?? sections.index(before: sections.endIndex)
        } else if customerFields.contains(field) {
            sections.lastIndex { section in
                section.fields.contains { customerFields.contains($0) }
            } ?? sections.index(before: sections.endIndex)
        } else if defaultBankFieldOrder.contains(field) {
            sections.firstIndex { section in
                section.fields.contains { defaultBankFieldOrder.contains($0) }
            } ?? sections.startIndex
        } else {
            sections.firstIndex { section in
                section.fields.contains { defaultCardFieldOrder.contains($0) }
            } ?? sections.startIndex
        }

        let section = sections[targetIndex]
        sections[targetIndex] = section.replacingFields(section.fields + [field])
    }

    private static func visibleBankFields(
        from fields: [PayabliPayInPaymentFlowField]
    ) -> [PayabliPayInPaymentFlowField] {
        fields.filter { $0 != .secCode }
    }

    private static func visibleRequiredFields(
        from fields: Set<PayabliPayInPaymentFlowField>
    ) -> Set<PayabliPayInPaymentFlowField> {
        fields.subtracting([.secCode])
    }

    private static func cardRequiredFields(
        from fields: Set<PayabliPayInPaymentFlowField>
    ) -> [PayabliPayInPaymentFlowField] {
        let supported = Set(defaultCardFieldOrder + customerFields + paymentDetailFields)
        return PayabliPayInPaymentFlowField.allCases.filter { fields.contains($0) && supported.contains($0) }
    }

    private static func bankRequiredFields(
        from fields: Set<PayabliPayInPaymentFlowField>
    ) -> [PayabliPayInPaymentFlowField] {
        let supported = Set(defaultBankFieldOrder + [.deviceId] + customerFields + paymentDetailFields)
        return PayabliPayInPaymentFlowField.allCases.filter { fields.contains($0) && supported.contains($0) }
    }

    private static let customerFields: [PayabliPayInPaymentFlowField] = [
        .methodDescription,
        .firstName,
        .lastName,
        .customerNumber,
        .billingEmail,
        .billingZip
    ]

    func replacingLabels(_ labels: PayabliPayInPaymentFlowLabels) -> PayabliPayInPaymentFlowFormConfiguration {
        PayabliPayInPaymentFlowFormConfiguration(
            allowedMethods: allowedMethods,
            defaultMethod: defaultMethod,
            cardFieldOrder: cardFieldOrder,
            bankFieldOrder: bankFieldOrder,
            cardSections: cardSections,
            bankSections: bankSections,
            hiddenValues: hiddenValues,
            options: options,
            labels: labels,
            labelLayout: labelLayout,
            showsFieldLabels: showsFieldLabels,
            hiddenFieldLabels: hiddenFieldLabels,
            formatting: formatting,
            inputSizing: inputSizing,
            cardBrandIconPlacement: cardBrandIconPlacement,
            errorMessagePlacement: errorMessagePlacement,
            requiredFields: requiredFields,
            paymentSummary: paymentSummary
        )
    }
}

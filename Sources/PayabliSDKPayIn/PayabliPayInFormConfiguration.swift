import Foundation
import SwiftUI

public enum PayabliPayInField: String, CaseIterable, Identifiable, Sendable {
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

public enum PayabliPayInLabelLayout: Sendable {
    case external
    case placeholder
}

public enum PayabliPayInCardBrandIconPlacement: Sendable, Equatable {
    case leading
    case trailing
    case hidden
}

public enum PayabliPayInErrorMessagePlacement: Sendable, Equatable {
    case top
    case aboveSubmitButton
}

public struct PayabliPayInFormatting: Sendable {
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

public struct PayabliPayInHiddenValues: Sendable {
    public let accountHolderType: PayabliPayInAccountHolderType?
    public let secCode: PayabliPayInSecCode?
    public let deviceId: String?
    public let methodDescription: String?
    public let customerData: PayabliPayInCustomerData?

    public init(
        accountHolderType: PayabliPayInAccountHolderType? = nil,
        secCode: PayabliPayInSecCode? = .web,
        deviceId: String? = nil,
        methodDescription: String? = nil,
        customerData: PayabliPayInCustomerData? = nil
    ) {
        self.accountHolderType = accountHolderType
        self.secCode = secCode
        self.deviceId = deviceId
        self.methodDescription = methodDescription
        self.customerData = customerData
    }
}

public typealias PayabliPayInOptions = PayabliPayInTokenStorageOptions

public struct PayabliPayInInputSize: Sendable, Equatable {
    public let width: CGFloat?
    public let height: CGFloat
    public let horizontalPadding: CGFloat

    public init(
        width: CGFloat? = nil,
        height: CGFloat = 52,
        horizontalPadding: CGFloat = 14
    ) {
        self.width = width
        self.height = max(PayabliPayInAccessibility.minimumTouchTarget, height)
        self.horizontalPadding = max(0, horizontalPadding)
    }
}

public struct PayabliPayInLabels: Sendable {
    public let title: String
    public let subtitle: String?
    public let submitButton: String
    public let fieldLabels: [PayabliPayInField: String]
    public let fieldPlaceholders: [PayabliPayInField: String]

    public init(
        title: String = "Save Payment Method",
        subtitle: String? = nil,
        submitButton: String = "Add Payment Method",
        fieldLabels: [PayabliPayInField: String] = Self.defaultFieldLabels,
        fieldPlaceholders: [PayabliPayInField: String] = [:]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.submitButton = submitButton
        self.fieldLabels = fieldLabels
        self.fieldPlaceholders = fieldPlaceholders
    }

    public func label(for field: PayabliPayInField) -> String {
        fieldLabels[field] ?? Self.defaultFieldLabels[field] ?? field.rawValue
    }

    public func placeholder(for field: PayabliPayInField) -> String? {
        fieldPlaceholders[field]?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
    }

    public static let defaultFieldLabels: [PayabliPayInField: String] = [
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

public struct PayabliPayInFieldSection: Identifiable, Sendable {
    public let id: String
    public let title: String?
    public let titleStyle: PayabliPayInTextStyle?
    public let fields: [PayabliPayInField]
    public let inputVerticalSpacing: CGFloat?
    public let inputHorizontalSpacing: CGFloat?
    public let fieldVerticalSpacings: [PayabliPayInField: CGFloat]

    public init(
        id: String? = nil,
        title: String? = nil,
        titleStyle: PayabliPayInTextStyle? = nil,
        fields: [PayabliPayInField],
        inputVerticalSpacing: CGFloat? = nil,
        inputHorizontalSpacing: CGFloat? = nil,
        fieldVerticalSpacings: [PayabliPayInField: CGFloat] = [:]
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

    func replacingFields(_ fields: [PayabliPayInField]) -> PayabliPayInFieldSection {
        PayabliPayInFieldSection(
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

public struct PayabliPayInInputSizing: Sendable, Equatable {
    public let defaultSize: PayabliPayInInputSize
    public let fieldSizes: [PayabliPayInField: PayabliPayInInputSize]

    public init(
        defaultSize: PayabliPayInInputSize = PayabliPayInInputSize(),
        fieldSizes: [PayabliPayInField: PayabliPayInInputSize] = [:]
    ) {
        self.defaultSize = defaultSize
        self.fieldSizes = fieldSizes
    }

    public func size(for field: PayabliPayInField) -> PayabliPayInInputSize {
        fieldSizes[field] ?? defaultSize
    }
}

public struct PayabliPayInPaymentSummaryTextStyle: Sendable {
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

public struct PayabliPayInPaymentSummaryConfiguration: Sendable {
    public let amountLabelText: String?
    public let amountValueText: String?
    public let feeLabelText: String?
    public let feeValueText: String?
    public let currencySymbol: String
    public let labelStyle: PayabliPayInPaymentSummaryTextStyle
    public let valueStyle: PayabliPayInPaymentSummaryTextStyle
    public let rowSpacing: CGFloat

    public init(
        amountLabelText: String? = nil,
        amountValueText: String? = nil,
        feeLabelText: String? = nil,
        feeValueText: String? = nil,
        currencySymbol: String = "$",
        labelStyle: PayabliPayInPaymentSummaryTextStyle = PayabliPayInPaymentSummaryTextStyle(
            font: .subheadline,
            color: .secondary
        ),
        valueStyle: PayabliPayInPaymentSummaryTextStyle = PayabliPayInPaymentSummaryTextStyle(
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
        for field: PayabliPayInField,
        labels: PayabliPayInLabels
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
        for field: PayabliPayInField,
        paymentDetails: PayabliPayInPaymentDetails?
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
        for field: PayabliPayInField,
        labels: PayabliPayInLabels,
        paymentDetails: PayabliPayInPaymentDetails?
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

public struct PayabliPayInFormConfiguration: Sendable {
    public let allowedMethods: [PayabliPayInMethodType]
    public let defaultMethod: PayabliPayInMethodType
    public let cardFieldOrder: [PayabliPayInField]
    public let bankFieldOrder: [PayabliPayInField]
    public let hiddenValues: PayabliPayInHiddenValues
    public let options: PayabliPayInOptions
    public let labels: PayabliPayInLabels
    public let labelLayout: PayabliPayInLabelLayout
    public let showsFieldLabels: Bool
    public let hiddenFieldLabels: Set<PayabliPayInField>
    public let formatting: PayabliPayInFormatting
    public let inputSizing: PayabliPayInInputSizing
    public let cardBrandIconPlacement: PayabliPayInCardBrandIconPlacement
    public let errorMessagePlacement: PayabliPayInErrorMessagePlacement
    public let requiredFields: Set<PayabliPayInField>
    public let cardSections: [PayabliPayInFieldSection]
    public let bankSections: [PayabliPayInFieldSection]
    public let paymentSummary: PayabliPayInPaymentSummaryConfiguration

    public init(
        allowedMethods: [PayabliPayInMethodType] = [.card, .bankAccount],
        defaultMethod: PayabliPayInMethodType = .card,
        cardFieldOrder: [PayabliPayInField] = Self.defaultCardFieldOrder,
        bankFieldOrder: [PayabliPayInField] = Self.defaultBankFieldOrder,
        cardSections: [PayabliPayInFieldSection]? = nil,
        bankSections: [PayabliPayInFieldSection]? = nil,
        hiddenValues: PayabliPayInHiddenValues = PayabliPayInHiddenValues(),
        options: PayabliPayInOptions = PayabliPayInOptions(),
        labels: PayabliPayInLabels = PayabliPayInLabels(),
        labelLayout: PayabliPayInLabelLayout = .external,
        showsFieldLabels: Bool? = nil,
        hiddenFieldLabels: Set<PayabliPayInField> = [],
        formatting: PayabliPayInFormatting = PayabliPayInFormatting(),
        inputSizing: PayabliPayInInputSizing = PayabliPayInInputSizing(),
        cardBrandIconPlacement: PayabliPayInCardBrandIconPlacement = .trailing,
        errorMessagePlacement: PayabliPayInErrorMessagePlacement = .aboveSubmitButton,
        requiredFields: Set<PayabliPayInField> = [],
        paymentSummary: PayabliPayInPaymentSummaryConfiguration = PayabliPayInPaymentSummaryConfiguration()
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

    public static let defaultCardFieldOrder: [PayabliPayInField] = [
        .cardholderName,
        .cardNumber,
        .cardExpiration,
        .cardCvv,
        .cardZip
    ]

    public static let defaultBankFieldOrder: [PayabliPayInField] = [
        .accountHolder,
        .routingNumber,
        .accountNumber,
        .accountType,
        .accountHolderType
    ]

    private static let requiredCardFields: [PayabliPayInField] = [
        .cardNumber,
        .cardExpiration,
        .cardholderName,
        .cardCvv,
        .cardZip,
        .amount
    ]

    private static let requiredBankFields: [PayabliPayInField] = [
        .accountHolder,
        .routingNumber,
        .accountNumber,
        .accountType,
        .amount
    ]

    private static let requiredPaymentFields: Set<PayabliPayInField> = [.amount]
    private static let paymentDetailFields: [PayabliPayInField] = [.amount, .serviceFee]

    private static func defaultCardSections(
        cardFieldOrder: [PayabliPayInField]
    ) -> [PayabliPayInFieldSection] {
        [
            PayabliPayInFieldSection(fields: cardFieldOrder),
            PayabliPayInFieldSection(title: "Payment Information", fields: paymentDetailFields)
        ]
    }

    private static func defaultBankSections(
        bankFieldOrder: [PayabliPayInField]
    ) -> [PayabliPayInFieldSection] {
        [
            PayabliPayInFieldSection(fields: visibleBankFields(from: bankFieldOrder)),
            PayabliPayInFieldSection(title: "Payment Information", fields: paymentDetailFields)
        ]
    }

    private static func normalizedSections(
        _ sections: [PayabliPayInFieldSection]?,
        defaultSections: [PayabliPayInFieldSection],
        required: [PayabliPayInField],
        appendedFields: [PayabliPayInField],
        hiddenFields: Set<PayabliPayInField> = []
    ) -> [PayabliPayInFieldSection] {
        let sourceSections = sections?.isEmpty == false ? sections ?? [] : defaultSections
        var seenFields = Set<PayabliPayInField>()
        var output = sourceSections.compactMap { section -> PayabliPayInFieldSection? in
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
        _ field: PayabliPayInField,
        to sections: inout [PayabliPayInFieldSection]
    ) {
        guard !sections.isEmpty else {
            sections = [PayabliPayInFieldSection(fields: [field])]
            return
        }

        if paymentDetailFields.contains(field),
           sections.contains(where: { section in section.fields.contains { paymentDetailFields.contains($0) } }) == false
        {
            sections.append(PayabliPayInFieldSection(title: "Payment Information", fields: [field]))
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
        from fields: [PayabliPayInField]
    ) -> [PayabliPayInField] {
        fields.filter { $0 != .secCode }
    }

    private static func visibleRequiredFields(
        from fields: Set<PayabliPayInField>
    ) -> Set<PayabliPayInField> {
        fields.subtracting([.secCode])
    }

    private static func cardRequiredFields(
        from fields: Set<PayabliPayInField>
    ) -> [PayabliPayInField] {
        let supported = Set(defaultCardFieldOrder + customerFields + paymentDetailFields)
        return PayabliPayInField.allCases.filter { fields.contains($0) && supported.contains($0) }
    }

    private static func bankRequiredFields(
        from fields: Set<PayabliPayInField>
    ) -> [PayabliPayInField] {
        let supported = Set(defaultBankFieldOrder + [.deviceId] + customerFields + paymentDetailFields)
        return PayabliPayInField.allCases.filter { fields.contains($0) && supported.contains($0) }
    }

    private static let customerFields: [PayabliPayInField] = [
        .methodDescription,
        .firstName,
        .lastName,
        .customerNumber,
        .billingEmail,
        .billingZip
    ]

    func replacingLabels(_ labels: PayabliPayInLabels) -> PayabliPayInFormConfiguration {
        PayabliPayInFormConfiguration(
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

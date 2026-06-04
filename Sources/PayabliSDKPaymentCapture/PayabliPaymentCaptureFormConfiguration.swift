import Foundation
import PayabliSDKPaymentMethod
import SwiftUI

public enum PayabliPaymentCaptureField: String, CaseIterable, Identifiable, Sendable {
    case cardholderName
    case cardNumber
    case cardExpiration
    case cardCvv
    case cardZip
    case achHolder
    case achRouting
    case achAccount
    case achAccountType
    case achHolderType
    case achSecCode
    case achDevice
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

public typealias PayabliPaymentCaptureLabelLayout = PayabliPaymentMethodLabelLayout
// swiftlint:disable:next type_name
public typealias PayabliPaymentCaptureCardBrandIconPlacement = PayabliPaymentMethodCardBrandIconPlacement
// swiftlint:disable:next type_name
public typealias PayabliPaymentCaptureErrorMessagePlacement = PayabliPaymentMethodErrorMessagePlacement
public typealias PayabliPaymentCaptureFormatting = PayabliPaymentMethodFormatting
public typealias PayabliPaymentCaptureHiddenValues = PayabliPaymentMethodHiddenValues
public typealias PayabliPaymentCaptureOptions = PayabliPaymentMethodOptions
public typealias PayabliPaymentCaptureInputSize = PayabliPaymentMethodInputSize
public typealias PayabliPaymentCaptureTextStyle = PayabliPaymentMethodTextStyle
public typealias PayabliPaymentCaptureInputStyle = PayabliPaymentMethodInputStyle
public typealias PayabliPaymentCaptureSubmitButtonStyle = PayabliPaymentMethodSubmitButtonStyle
public typealias PayabliPaymentCaptureLayoutStyle = PayabliPaymentMethodLayoutStyle
public typealias PayabliPaymentCaptureStyle = PayabliPaymentMethodStyle
public typealias PayabliPaymentCaptureSheetDismissButton = PayabliPaymentMethodSheetDismissButton
public typealias PayabliPaymentCaptureSheetConfiguration = PayabliPaymentMethodSheetConfiguration

public struct PayabliPaymentCaptureLabels: Sendable {
    public let title: String
    public let subtitle: String?
    public let submitButton: String
    public let fieldLabels: [PayabliPaymentCaptureField: String]
    public let fieldPlaceholders: [PayabliPaymentCaptureField: String]

    public init(
        title: String = "Payment Capture",
        subtitle: String? = nil,
        submitButton: String = "Submit Payment",
        fieldLabels: [PayabliPaymentCaptureField: String] = Self.defaultFieldLabels,
        fieldPlaceholders: [PayabliPaymentCaptureField: String] = [:]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.submitButton = submitButton
        self.fieldLabels = fieldLabels
        self.fieldPlaceholders = fieldPlaceholders
    }

    public func label(for field: PayabliPaymentCaptureField) -> String {
        fieldLabels[field] ?? Self.defaultFieldLabels[field] ?? field.rawValue
    }

    public func placeholder(for field: PayabliPaymentCaptureField) -> String? {
        fieldPlaceholders[field]?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
    }

    public static let defaultFieldLabels: [PayabliPaymentCaptureField: String] = [
        .cardholderName: "Name on card",
        .cardNumber: "Card number",
        .cardExpiration: "Expiration",
        .cardCvv: "CVV",
        .cardZip: "Postal Code",
        .achHolder: "Account holder",
        .achRouting: "Routing number",
        .achAccount: "Account number",
        .achAccountType: "Account type",
        .achHolderType: "Holder type",
        .achSecCode: "SEC code",
        .achDevice: "Device",
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

public struct PayabliPaymentCaptureFieldSection: Identifiable, Sendable {
    public let id: String
    public let title: String?
    public let titleStyle: PayabliPaymentCaptureTextStyle?
    public let fields: [PayabliPaymentCaptureField]
    public let inputVerticalSpacing: CGFloat?
    public let inputHorizontalSpacing: CGFloat?
    public let fieldVerticalSpacings: [PayabliPaymentCaptureField: CGFloat]

    public init(
        id: String? = nil,
        title: String? = nil,
        titleStyle: PayabliPaymentCaptureTextStyle? = nil,
        fields: [PayabliPaymentCaptureField],
        inputVerticalSpacing: CGFloat? = nil,
        inputHorizontalSpacing: CGFloat? = nil,
        fieldVerticalSpacings: [PayabliPaymentCaptureField: CGFloat] = [:]
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

    func replacingFields(_ fields: [PayabliPaymentCaptureField]) -> PayabliPaymentCaptureFieldSection {
        PayabliPaymentCaptureFieldSection(
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

public struct PayabliPaymentCaptureInputSizing: Sendable, Equatable {
    public let defaultSize: PayabliPaymentCaptureInputSize
    public let fieldSizes: [PayabliPaymentCaptureField: PayabliPaymentCaptureInputSize]

    public init(
        defaultSize: PayabliPaymentCaptureInputSize = PayabliPaymentCaptureInputSize(),
        fieldSizes: [PayabliPaymentCaptureField: PayabliPaymentCaptureInputSize] = [:]
    ) {
        self.defaultSize = defaultSize
        self.fieldSizes = fieldSizes
    }

    public func size(for field: PayabliPaymentCaptureField) -> PayabliPaymentCaptureInputSize {
        fieldSizes[field] ?? defaultSize
    }
}

// Public API keeps the PaymentCapture namespace for discoverability.
// swiftlint:disable:next type_name
public struct PayabliPaymentCapturePaymentSummaryTextStyle: Sendable {
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

// Public API keeps the PaymentCapture namespace for discoverability.
// swiftlint:disable:next type_name
public struct PayabliPaymentCapturePaymentSummaryConfiguration: Sendable {
    public let amountLabelText: String?
    public let amountValueText: String?
    public let feeLabelText: String?
    public let feeValueText: String?
    public let currencySymbol: String
    public let labelStyle: PayabliPaymentCapturePaymentSummaryTextStyle
    public let valueStyle: PayabliPaymentCapturePaymentSummaryTextStyle
    public let rowSpacing: CGFloat

    public init(
        amountLabelText: String? = nil,
        amountValueText: String? = nil,
        feeLabelText: String? = nil,
        feeValueText: String? = nil,
        currencySymbol: String = "$",
        labelStyle: PayabliPaymentCapturePaymentSummaryTextStyle = PayabliPaymentCapturePaymentSummaryTextStyle(
            font: .subheadline,
            color: .secondary
        ),
        valueStyle: PayabliPaymentCapturePaymentSummaryTextStyle = PayabliPaymentCapturePaymentSummaryTextStyle(
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
        for field: PayabliPaymentCaptureField,
        labels: PayabliPaymentCaptureLabels
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
        for field: PayabliPaymentCaptureField,
        paymentDetails: PayabliPaymentCapturePaymentDetails?
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
        for field: PayabliPaymentCaptureField,
        labels: PayabliPaymentCaptureLabels,
        paymentDetails: PayabliPaymentCapturePaymentDetails?
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

public struct PayabliPaymentCaptureFormConfiguration: Sendable {
    public let allowedMethods: [PayabliPaymentMethodType]
    public let defaultMethod: PayabliPaymentMethodType
    public let cardFieldOrder: [PayabliPaymentCaptureField]
    public let achFieldOrder: [PayabliPaymentCaptureField]
    public let hiddenValues: PayabliPaymentCaptureHiddenValues
    public let options: PayabliPaymentCaptureOptions
    public let labels: PayabliPaymentCaptureLabels
    public let labelLayout: PayabliPaymentCaptureLabelLayout
    public let showsFieldLabels: Bool
    public let hiddenFieldLabels: Set<PayabliPaymentCaptureField>
    public let formatting: PayabliPaymentCaptureFormatting
    public let inputSizing: PayabliPaymentCaptureInputSizing
    public let cardBrandIconPlacement: PayabliPaymentCaptureCardBrandIconPlacement
    public let errorMessagePlacement: PayabliPaymentCaptureErrorMessagePlacement
    public let requiredFields: Set<PayabliPaymentCaptureField>
    public let cardSections: [PayabliPaymentCaptureFieldSection]
    public let achSections: [PayabliPaymentCaptureFieldSection]
    public let paymentSummary: PayabliPaymentCapturePaymentSummaryConfiguration

    public init(
        allowedMethods: [PayabliPaymentMethodType] = [.card, .ach],
        defaultMethod: PayabliPaymentMethodType = .card,
        cardFieldOrder: [PayabliPaymentCaptureField] = Self.defaultCardFieldOrder,
        achFieldOrder: [PayabliPaymentCaptureField] = Self.defaultACHFieldOrder,
        cardSections: [PayabliPaymentCaptureFieldSection]? = nil,
        achSections: [PayabliPaymentCaptureFieldSection]? = nil,
        hiddenValues: PayabliPaymentCaptureHiddenValues = PayabliPaymentCaptureHiddenValues(),
        options: PayabliPaymentCaptureOptions = PayabliPaymentCaptureOptions(),
        labels: PayabliPaymentCaptureLabels = PayabliPaymentCaptureLabels(),
        labelLayout: PayabliPaymentCaptureLabelLayout = .external,
        showsFieldLabels: Bool? = nil,
        hiddenFieldLabels: Set<PayabliPaymentCaptureField> = [],
        formatting: PayabliPaymentCaptureFormatting = PayabliPaymentCaptureFormatting(),
        inputSizing: PayabliPaymentCaptureInputSizing = PayabliPaymentCaptureInputSizing(),
        cardBrandIconPlacement: PayabliPaymentCaptureCardBrandIconPlacement = .trailing,
        errorMessagePlacement: PayabliPaymentCaptureErrorMessagePlacement = .aboveSubmitButton,
        requiredFields: Set<PayabliPaymentCaptureField> = [],
        paymentSummary: PayabliPaymentCapturePaymentSummaryConfiguration = PayabliPaymentCapturePaymentSummaryConfiguration()
    ) {
        let methods = allowedMethods.isEmpty ? [defaultMethod] : allowedMethods
        let visibleRequiredFields = Self.visibleRequiredFields(from: requiredFields)
        let requiredCardFields = Self.requiredCardFields + Self.cardRequiredFields(from: visibleRequiredFields)
        let requiredACHFields = Self.requiredACHFields + Self.achRequiredFields(from: visibleRequiredFields)
        let normalizedCardSections = Self.normalizedSections(
            cardSections,
            defaultSections: Self.defaultCardSections(cardFieldOrder: cardFieldOrder),
            required: requiredCardFields,
            appendedFields: Self.paymentDetailFields
        )
        let normalizedACHSections = Self.normalizedSections(
            achSections,
            defaultSections: Self.defaultACHSections(achFieldOrder: achFieldOrder),
            required: requiredACHFields,
            appendedFields: Self.paymentDetailFields,
            hiddenFields: [.achSecCode]
        )
        self.allowedMethods = methods
        self.defaultMethod = methods.contains(defaultMethod) ? defaultMethod : methods[0]
        self.cardFieldOrder = normalizedCardSections.flatMap(\.fields)
        self.achFieldOrder = normalizedACHSections.flatMap(\.fields)
        self.cardSections = normalizedCardSections
        self.achSections = normalizedACHSections
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

    public static let defaultCardFieldOrder: [PayabliPaymentCaptureField] = [
        .cardholderName,
        .cardNumber,
        .cardExpiration,
        .cardCvv,
        .cardZip
    ]

    public static let defaultACHFieldOrder: [PayabliPaymentCaptureField] = [
        .achHolder,
        .achRouting,
        .achAccount,
        .achAccountType,
        .achHolderType
    ]

    private static let requiredCardFields: [PayabliPaymentCaptureField] = [
        .cardNumber,
        .cardExpiration,
        .cardholderName,
        .cardCvv,
        .cardZip,
        .amount
    ]

    private static let requiredACHFields: [PayabliPaymentCaptureField] = [
        .achHolder,
        .achRouting,
        .achAccount,
        .achAccountType,
        .amount
    ]

    private static let requiredPaymentFields: Set<PayabliPaymentCaptureField> = [.amount]
    private static let paymentDetailFields: [PayabliPaymentCaptureField] = [.amount, .serviceFee]

    private static func defaultCardSections(
        cardFieldOrder: [PayabliPaymentCaptureField]
    ) -> [PayabliPaymentCaptureFieldSection] {
        [
            PayabliPaymentCaptureFieldSection(fields: cardFieldOrder),
            PayabliPaymentCaptureFieldSection(title: "Payment Information", fields: paymentDetailFields)
        ]
    }

    private static func defaultACHSections(
        achFieldOrder: [PayabliPaymentCaptureField]
    ) -> [PayabliPaymentCaptureFieldSection] {
        [
            PayabliPaymentCaptureFieldSection(fields: visibleACHFields(from: achFieldOrder)),
            PayabliPaymentCaptureFieldSection(title: "Payment Information", fields: paymentDetailFields)
        ]
    }

    private static func normalizedSections(
        _ sections: [PayabliPaymentCaptureFieldSection]?,
        defaultSections: [PayabliPaymentCaptureFieldSection],
        required: [PayabliPaymentCaptureField],
        appendedFields: [PayabliPaymentCaptureField],
        hiddenFields: Set<PayabliPaymentCaptureField> = []
    ) -> [PayabliPaymentCaptureFieldSection] {
        let sourceSections = sections?.isEmpty == false ? sections ?? [] : defaultSections
        var seenFields = Set<PayabliPaymentCaptureField>()
        var output = sourceSections.compactMap { section -> PayabliPaymentCaptureFieldSection? in
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
        _ field: PayabliPaymentCaptureField,
        to sections: inout [PayabliPaymentCaptureFieldSection]
    ) {
        guard !sections.isEmpty else {
            sections = [PayabliPaymentCaptureFieldSection(fields: [field])]
            return
        }

        if paymentDetailFields.contains(field),
           sections.contains(where: { section in section.fields.contains { paymentDetailFields.contains($0) } }) == false
        {
            sections.append(PayabliPaymentCaptureFieldSection(title: "Payment Information", fields: [field]))
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
        } else if defaultACHFieldOrder.contains(field) {
            sections.firstIndex { section in
                section.fields.contains { defaultACHFieldOrder.contains($0) }
            } ?? sections.startIndex
        } else {
            sections.firstIndex { section in
                section.fields.contains { defaultCardFieldOrder.contains($0) }
            } ?? sections.startIndex
        }

        let section = sections[targetIndex]
        sections[targetIndex] = section.replacingFields(section.fields + [field])
    }

    private static func visibleACHFields(
        from fields: [PayabliPaymentCaptureField]
    ) -> [PayabliPaymentCaptureField] {
        fields.filter { $0 != .achSecCode }
    }

    private static func visibleRequiredFields(
        from fields: Set<PayabliPaymentCaptureField>
    ) -> Set<PayabliPaymentCaptureField> {
        fields.subtracting([.achSecCode])
    }

    private static func cardRequiredFields(
        from fields: Set<PayabliPaymentCaptureField>
    ) -> [PayabliPaymentCaptureField] {
        let supported = Set(defaultCardFieldOrder + customerFields + paymentDetailFields)
        return PayabliPaymentCaptureField.allCases.filter { fields.contains($0) && supported.contains($0) }
    }

    private static func achRequiredFields(
        from fields: Set<PayabliPaymentCaptureField>
    ) -> [PayabliPaymentCaptureField] {
        let supported = Set(defaultACHFieldOrder + [.achDevice] + customerFields + paymentDetailFields)
        return PayabliPaymentCaptureField.allCases.filter { fields.contains($0) && supported.contains($0) }
    }

    private static let customerFields: [PayabliPaymentCaptureField] = [
        .methodDescription,
        .firstName,
        .lastName,
        .customerNumber,
        .billingEmail,
        .billingZip
    ]

    func replacingLabels(_ labels: PayabliPaymentCaptureLabels) -> PayabliPaymentCaptureFormConfiguration {
        PayabliPaymentCaptureFormConfiguration(
            allowedMethods: allowedMethods,
            defaultMethod: defaultMethod,
            cardFieldOrder: cardFieldOrder,
            achFieldOrder: achFieldOrder,
            cardSections: cardSections,
            achSections: achSections,
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

public extension View {
    func payabliPaymentCaptureStyle(_ style: PayabliPaymentCaptureStyle) -> some View {
        payabliPaymentMethodStyle(style)
    }
}

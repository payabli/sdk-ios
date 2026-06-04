import PayabliSDKCore
import SwiftUI
import UIKit

public enum PayabliPaymentMethodField: String, CaseIterable, Identifiable, Sendable {
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

    public var id: String {
        rawValue
    }
}

public enum PayabliPaymentMethodLabelLayout: Sendable {
    case external
    case placeholder
}

// Public API keeps the PaymentMethod namespace for discoverability.
// swiftlint:disable:next type_name
public enum PayabliPaymentMethodCardBrandIconPlacement: Sendable, Equatable {
    case leading
    case trailing
    case hidden
}

// Public API keeps the PaymentMethod namespace for discoverability.
// swiftlint:disable:next type_name
public enum PayabliPaymentMethodErrorMessagePlacement: Sendable, Equatable {
    case top
    case aboveSubmitButton
}

public struct PayabliPaymentMethodFormatting: Sendable {
    public let insertsCardNumberSpaces: Bool
    public let expirationSeparator: String
    public let masksACHAccountEntry: Bool

    public init(
        insertsCardNumberSpaces: Bool = true,
        expirationSeparator: String = "/",
        masksACHAccountEntry: Bool = true
    ) {
        self.insertsCardNumberSpaces = insertsCardNumberSpaces
        self.expirationSeparator = expirationSeparator.isEmpty ? "/" : expirationSeparator
        self.masksACHAccountEntry = masksACHAccountEntry
    }
}

public struct PayabliPaymentMethodHiddenValues: Sendable {
    public let achHolderType: PayabliACHHolderType?
    public let achSecCode: PayabliACHSecCode?
    public let achDevice: String?
    public let methodDescription: String?
    public let customerData: PayabliPaymentMethodCustomerData?

    public init(
        achHolderType: PayabliACHHolderType? = nil,
        achSecCode: PayabliACHSecCode? = .web,
        achDevice: String? = nil,
        methodDescription: String? = nil,
        customerData: PayabliPaymentMethodCustomerData? = nil
    ) {
        self.achHolderType = achHolderType
        self.achSecCode = achSecCode
        self.achDevice = achDevice
        self.methodDescription = methodDescription
        self.customerData = customerData
    }
}

public struct PayabliPaymentMethodLabels: Sendable {
    public let title: String
    public let subtitle: String?
    public let submitButton: String
    public let fieldLabels: [PayabliPaymentMethodField: String]
    public let fieldPlaceholders: [PayabliPaymentMethodField: String]

    public init(
        title: String = "Save Payment Method",
        subtitle: String? = nil,
        submitButton: String = "Add Payment Method",
        fieldLabels: [PayabliPaymentMethodField: String] = Self.defaultFieldLabels,
        fieldPlaceholders: [PayabliPaymentMethodField: String] = [:]
    ) {
        self.title = title
        self.subtitle = subtitle
        self.submitButton = submitButton
        self.fieldLabels = fieldLabels
        self.fieldPlaceholders = fieldPlaceholders
    }

    public func label(for field: PayabliPaymentMethodField) -> String {
        fieldLabels[field] ?? Self.defaultFieldLabels[field] ?? field.rawValue
    }

    public func placeholder(for field: PayabliPaymentMethodField) -> String? {
        fieldPlaceholders[field]?.trimmed.nilIfEmpty
    }

    public static let defaultFieldLabels: [PayabliPaymentMethodField: String] = [
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
        .billingZip: "Billing Postal Code"
    ]
}

public struct PayabliPaymentMethodFieldSection: Identifiable, Sendable, Equatable {
    public let id: String
    public let title: String?
    public let fields: [PayabliPaymentMethodField]
    public let inputVerticalSpacing: CGFloat?
    public let inputHorizontalSpacing: CGFloat?
    public let fieldVerticalSpacings: [PayabliPaymentMethodField: CGFloat]

    public init(
        id: String? = nil,
        title: String? = nil,
        fields: [PayabliPaymentMethodField],
        inputVerticalSpacing: CGFloat? = nil,
        inputHorizontalSpacing: CGFloat? = nil,
        fieldVerticalSpacings: [PayabliPaymentMethodField: CGFloat] = [:]
    ) {
        let resolvedTitle = title?.trimmed.nilIfEmpty
        self.id = id?.trimmed.nilIfEmpty
            ?? resolvedTitle
            ?? fields.map(\.rawValue).joined(separator: "-")
        self.title = resolvedTitle
        self.fields = fields
        self.inputVerticalSpacing = inputVerticalSpacing.map { max(0, $0) }
        self.inputHorizontalSpacing = inputHorizontalSpacing.map { max(0, $0) }
        self.fieldVerticalSpacings = fieldVerticalSpacings.mapValues { max(0, $0) }
    }

    func replacingFields(_ fields: [PayabliPaymentMethodField]) -> PayabliPaymentMethodFieldSection {
        PayabliPaymentMethodFieldSection(
            id: id,
            title: title,
            fields: fields,
            inputVerticalSpacing: inputVerticalSpacing,
            inputHorizontalSpacing: inputHorizontalSpacing,
            fieldVerticalSpacings: fieldVerticalSpacings
        )
    }
}

public struct PayabliPaymentMethodInputSize: Sendable, Equatable {
    public let width: CGFloat?
    public let height: CGFloat
    public let horizontalPadding: CGFloat

    public init(
        width: CGFloat? = nil,
        height: CGFloat = 52,
        horizontalPadding: CGFloat = 14
    ) {
        self.width = width
        self.height = max(PayabliPaymentMethodAccessibility.minimumTouchTarget, height)
        self.horizontalPadding = max(0, horizontalPadding)
    }
}

public struct PayabliPaymentMethodInputSizing: Sendable, Equatable {
    public let defaultSize: PayabliPaymentMethodInputSize
    public let fieldSizes: [PayabliPaymentMethodField: PayabliPaymentMethodInputSize]

    public init(
        defaultSize: PayabliPaymentMethodInputSize = PayabliPaymentMethodInputSize(),
        fieldSizes: [PayabliPaymentMethodField: PayabliPaymentMethodInputSize] = [:]
    ) {
        self.defaultSize = defaultSize
        self.fieldSizes = fieldSizes
    }

    public func size(for field: PayabliPaymentMethodField) -> PayabliPaymentMethodInputSize {
        fieldSizes[field] ?? defaultSize
    }
}

public struct PayabliPaymentMethodFormConfiguration: Sendable {
    public let allowedMethods: [PayabliPaymentMethodType]
    public let defaultMethod: PayabliPaymentMethodType
    public let cardFieldOrder: [PayabliPaymentMethodField]
    public let achFieldOrder: [PayabliPaymentMethodField]
    public let hiddenValues: PayabliPaymentMethodHiddenValues
    public let options: PayabliPaymentMethodOptions
    public let labels: PayabliPaymentMethodLabels
    public let labelLayout: PayabliPaymentMethodLabelLayout
    public let showsFieldLabels: Bool
    public let hiddenFieldLabels: Set<PayabliPaymentMethodField>
    public let formatting: PayabliPaymentMethodFormatting
    public let inputSizing: PayabliPaymentMethodInputSizing
    public let cardBrandIconPlacement: PayabliPaymentMethodCardBrandIconPlacement
    public let errorMessagePlacement: PayabliPaymentMethodErrorMessagePlacement
    public let requiredFields: Set<PayabliPaymentMethodField>
    public let cardSections: [PayabliPaymentMethodFieldSection]
    public let achSections: [PayabliPaymentMethodFieldSection]

    public init(
        allowedMethods: [PayabliPaymentMethodType] = [.card, .ach],
        defaultMethod: PayabliPaymentMethodType = .card,
        cardFieldOrder: [PayabliPaymentMethodField] = Self.defaultCardFieldOrder,
        achFieldOrder: [PayabliPaymentMethodField] = Self.defaultACHFieldOrder,
        cardSections: [PayabliPaymentMethodFieldSection]? = nil,
        achSections: [PayabliPaymentMethodFieldSection]? = nil,
        hiddenValues: PayabliPaymentMethodHiddenValues = PayabliPaymentMethodHiddenValues(),
        options: PayabliPaymentMethodOptions = PayabliPaymentMethodOptions(),
        labels: PayabliPaymentMethodLabels = PayabliPaymentMethodLabels(),
        labelLayout: PayabliPaymentMethodLabelLayout = .external,
        showsFieldLabels: Bool? = nil,
        hiddenFieldLabels: Set<PayabliPaymentMethodField> = [],
        formatting: PayabliPaymentMethodFormatting = PayabliPaymentMethodFormatting(),
        inputSizing: PayabliPaymentMethodInputSizing = PayabliPaymentMethodInputSizing(),
        cardBrandIconPlacement: PayabliPaymentMethodCardBrandIconPlacement = .trailing,
        errorMessagePlacement: PayabliPaymentMethodErrorMessagePlacement = .aboveSubmitButton,
        requiredFields: Set<PayabliPaymentMethodField> = []
    ) {
        let methods = allowedMethods.isEmpty ? [defaultMethod] : allowedMethods
        let visibleRequiredFields = Self.visibleRequiredFields(from: requiredFields)
        let requiredCardFields = Self.requiredCardFields + Self.cardRequiredFields(from: visibleRequiredFields)
        let requiredACHFields = Self.requiredACHFields + Self.achRequiredFields(from: visibleRequiredFields)
        let normalizedCardSections = Self.normalizedSections(
            cardSections,
            defaultFields: Self.includingRequiredFields(
                cardFieldOrder,
                required: requiredCardFields
            ),
            required: requiredCardFields
        )
        let normalizedACHSections = Self.normalizedSections(
            achSections,
            defaultFields: Self.includingRequiredFields(
                Self.visibleACHFields(from: achFieldOrder),
                required: requiredACHFields
            ),
            required: requiredACHFields,
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
        self.requiredFields = visibleRequiredFields
    }

    public static let defaultCardFieldOrder: [PayabliPaymentMethodField] = [
        .cardholderName,
        .cardNumber,
        .cardExpiration,
        .cardCvv,
        .cardZip
    ]

    public static let defaultACHFieldOrder: [PayabliPaymentMethodField] = [
        .achHolder,
        .achRouting,
        .achAccount,
        .achAccountType,
        .achHolderType
    ]

    private static let requiredCardFields: [PayabliPaymentMethodField] = [
        .cardNumber,
        .cardExpiration,
        .cardholderName,
        .cardCvv,
        .cardZip
    ]

    private static let requiredACHFields: [PayabliPaymentMethodField] = [
        .achHolder,
        .achRouting,
        .achAccount,
        .achAccountType
    ]

    private static func includingRequiredFields(
        _ fields: [PayabliPaymentMethodField],
        required: [PayabliPaymentMethodField]
    ) -> [PayabliPaymentMethodField] {
        var output = fields
        for field in required where !output.contains(field) {
            output.append(field)
        }
        return output
    }

    private static func normalizedSections(
        _ sections: [PayabliPaymentMethodFieldSection]?,
        defaultFields: [PayabliPaymentMethodField],
        required: [PayabliPaymentMethodField],
        hiddenFields: Set<PayabliPaymentMethodField> = []
    ) -> [PayabliPaymentMethodFieldSection] {
        let sourceSections = sections?.isEmpty == false
            ? sections ?? []
            : [PayabliPaymentMethodFieldSection(fields: defaultFields)]
        var seenFields = Set<PayabliPaymentMethodField>()
        var output = sourceSections.compactMap { section -> PayabliPaymentMethodFieldSection? in
            let visibleFields = section.fields.filter { field in
                !hiddenFields.contains(field) && seenFields.insert(field).inserted
            }
            guard !visibleFields.isEmpty else { return nil }
            return section.replacingFields(visibleFields)
        }

        for field in required where !hiddenFields.contains(field) && !seenFields.contains(field) {
            append(field, to: &output)
            seenFields.insert(field)
        }

        return output
    }

    private static func append(
        _ field: PayabliPaymentMethodField,
        to sections: inout [PayabliPaymentMethodFieldSection]
    ) {
        guard !sections.isEmpty else {
            sections = [PayabliPaymentMethodFieldSection(fields: [field])]
            return
        }

        let targetIndex: Int = if customerFields.contains(field) {
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

    private static func visibleACHFields(from fields: [PayabliPaymentMethodField]) -> [PayabliPaymentMethodField] {
        fields.filter { $0 != .achSecCode }
    }

    private static func visibleRequiredFields(
        from fields: Set<PayabliPaymentMethodField>
    ) -> Set<PayabliPaymentMethodField> {
        fields.subtracting([.achSecCode])
    }

    private static func cardRequiredFields(
        from fields: Set<PayabliPaymentMethodField>
    ) -> [PayabliPaymentMethodField] {
        let supported = Set(defaultCardFieldOrder + customerFields)
        return PayabliPaymentMethodField.allCases.filter { fields.contains($0) && supported.contains($0) }
    }

    private static func achRequiredFields(
        from fields: Set<PayabliPaymentMethodField>
    ) -> [PayabliPaymentMethodField] {
        let supported = Set(defaultACHFieldOrder + [.achDevice] + customerFields)
        return PayabliPaymentMethodField.allCases.filter { fields.contains($0) && supported.contains($0) }
    }

    private static let customerFields: [PayabliPaymentMethodField] = [
        .methodDescription,
        .firstName,
        .lastName,
        .customerNumber,
        .billingEmail,
        .billingZip
    ]

    func replacingLabels(_ labels: PayabliPaymentMethodLabels) -> PayabliPaymentMethodFormConfiguration {
        PayabliPaymentMethodFormConfiguration(
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
            requiredFields: requiredFields
        )
    }
}

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

public enum PayabliPaymentMethodCardBrandIconPlacement: Sendable, Equatable {
    case leading
    case trailing
    case hidden
}

public enum PayabliPaymentMethodErrorMessagePlacement: Sendable, Equatable {
    case top
    case aboveSubmitButton
}

public struct PayabliPaymentMethodFormatting: Sendable {
    public var insertsCardNumberSpaces: Bool
    public var expirationSeparator: String
    public var masksACHAccountEntry: Bool

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
    public var achHolderType: PayabliACHHolderType?
    public var achSecCode: PayabliACHSecCode?
    public var achDevice: String?
    public var methodDescription: String?
    public var customerData: PayabliPaymentMethodCustomerData?

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
    public var title: String
    public var subtitle: String?
    public var submitButton: String
    public var fieldLabels: [PayabliPaymentMethodField: String]
    public var fieldPlaceholders: [PayabliPaymentMethodField: String]

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
    public var id: String
    public var title: String?
    public var fields: [PayabliPaymentMethodField]
    public var inputVerticalSpacing: CGFloat?
    public var inputHorizontalSpacing: CGFloat?
    public var fieldVerticalSpacings: [PayabliPaymentMethodField: CGFloat]

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
    public var width: CGFloat?
    public var height: CGFloat
    public var horizontalPadding: CGFloat

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
    public var defaultSize: PayabliPaymentMethodInputSize
    public var fieldSizes: [PayabliPaymentMethodField: PayabliPaymentMethodInputSize]

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
    public var allowedMethods: [PayabliPaymentMethodType]
    public var defaultMethod: PayabliPaymentMethodType
    public var cardFieldOrder: [PayabliPaymentMethodField]
    public var achFieldOrder: [PayabliPaymentMethodField]
    public var hiddenValues: PayabliPaymentMethodHiddenValues
    public var options: PayabliPaymentMethodOptions
    public var labels: PayabliPaymentMethodLabels
    public var labelLayout: PayabliPaymentMethodLabelLayout
    public var showsFieldLabels: Bool
    public var hiddenFieldLabels: Set<PayabliPaymentMethodField>
    public var formatting: PayabliPaymentMethodFormatting
    public var inputSizing: PayabliPaymentMethodInputSizing
    public var cardBrandIconPlacement: PayabliPaymentMethodCardBrandIconPlacement
    public var errorMessagePlacement: PayabliPaymentMethodErrorMessagePlacement
    public var requiredFields: Set<PayabliPaymentMethodField>
    public var cardSections: [PayabliPaymentMethodFieldSection]
    public var achSections: [PayabliPaymentMethodFieldSection]

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

        let targetIndex: Int
        if customerFields.contains(field) {
            targetIndex = sections.lastIndex { section in
                section.fields.contains { customerFields.contains($0) }
            } ?? sections.index(before: sections.endIndex)
        } else if defaultACHFieldOrder.contains(field) {
            targetIndex = sections.firstIndex { section in
                section.fields.contains { defaultACHFieldOrder.contains($0) }
            } ?? sections.startIndex
        } else {
            targetIndex = sections.firstIndex { section in
                section.fields.contains { defaultCardFieldOrder.contains($0) }
            } ?? sections.startIndex
        }

        sections[targetIndex].fields.append(field)
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
}

public struct PayabliPaymentMethodView: View {
    @StateObject private var viewModel: PayabliPaymentMethodViewModel
    @State private var isExpirationPickerPresented = false
    @FocusState private var focusedField: PayabliPaymentMethodField?
    @AccessibilityFocusState private var isErrorAccessibilityFocused: Bool
    @Environment(\.payabliPaymentMethodStyle) private var environmentStyle
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let configuration: PayabliPaymentMethodFormConfiguration
    private let explicitStyle: PayabliPaymentMethodStyle?
    private let onPaymentMethodAdded: (PayabliStoredPaymentMethod) -> Void
    private let onError: (Error) -> Void

    @MainActor
    public init(
        component: PayabliPaymentMethod,
        configuration: PayabliPaymentMethodFormConfiguration = PayabliPaymentMethodFormConfiguration(),
        style: PayabliPaymentMethodStyle? = nil,
        onPaymentMethodAdded: @escaping (PayabliStoredPaymentMethod) -> Void,
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.explicitStyle = style
        self.onPaymentMethodAdded = onPaymentMethodAdded
        self.onError = onError
        _viewModel = StateObject(wrappedValue: PayabliPaymentMethodViewModel(
            component: component,
            configuration: configuration
        ))
    }

    private var resolvedStyle: PayabliPaymentMethodStyle {
        explicitStyle ?? environmentStyle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: resolvedStyle.layout.contentSpacing) {
            header

            if configuration.errorMessagePlacement == .top {
                errorMessageView
            }

            if configuration.allowedMethods.count > 1 {
                methodSelector
            }

            VStack(alignment: .leading, spacing: resolvedStyle.layout.sectionSpacing) {
                ForEach(Array(activeSections.enumerated()), id: \.offset) { _, section in
                    fieldSection(section)
                }
            }

            if configuration.errorMessagePlacement == .aboveSubmitButton {
                errorMessageView
            }

            submitButton
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .privacySensitive()
        .sheet(isPresented: $isExpirationPickerPresented) {
            expirationWheelSheet
        }
        .onChange(of: viewModel.errorMessage) { message in
            announceErrorMessage(message)
        }
        .onChange(of: viewModel.cardNumberValidationMessage) { message in
            announceFieldError(
                field: .cardNumber,
                message: message
            )
        }
    }

    @ViewBuilder
    private var errorMessageView: some View {
        if let errorMessage = viewModel.errorMessage {
            errorText(errorMessage)
                .accessibilityFocused($isErrorAccessibilityFocused)
        }
    }

    @ViewBuilder
    private var header: some View {
        let title = configuration.labels.title.trimmed
        let subtitle = configuration.labels.subtitle?.trimmed.nilIfEmpty

        if !title.isEmpty || subtitle != nil {
            VStack(alignment: .leading, spacing: resolvedStyle.layout.headerSpacing) {
                if !title.isEmpty {
                    Text(title)
                        .font(resolvedStyle.title.font)
                        .foregroundStyle(resolvedStyle.title.color)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                }

                if let subtitle {
                    Text(subtitle)
                        .font(resolvedStyle.subtitle.font)
                        .foregroundStyle(resolvedStyle.subtitle.color)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    private var methodSelector: some View {
        Picker("Payment method", selection: $viewModel.selectedMethod) {
            ForEach(configuration.allowedMethods) { method in
                Text(method.displayName).tag(method)
            }
        }
        .pickerStyle(.segmented)
        .tint(resolvedStyle.accentColor)
        .accessibilityLabel("Payment method")
        .accessibilityValue(viewModel.selectedMethod.displayName)
        .accessibilityHint("Selects the payment method type.")
    }

    private var activeSections: [PayabliPaymentMethodFieldSection] {
        switch viewModel.selectedMethod {
        case .card:
            return configuration.cardSections
        case .ach:
            return configuration.achSections
        }
    }

    private func fieldGroups(
        for fields: [PayabliPaymentMethodField]
    ) -> [[PayabliPaymentMethodField]] {
        var groups: [[PayabliPaymentMethodField]] = []
        var index = fields.startIndex

        while index < fields.endIndex {
            let field = fields[index]
            let nextIndex = fields.index(after: index)
            if nextIndex < fields.endIndex {
                let next = fields[nextIndex]
                if shouldPair(field, next) {
                    groups.append([field, next])
                    index = fields.index(after: nextIndex)
                    continue
                }
            }

            groups.append([field])
            index = nextIndex
        }

        return groups
    }

    private var submitButton: some View {
        Button {
            Task {
                do {
                    let result = try await viewModel.submit()
                    onPaymentMethodAdded(result)
                } catch {
                    onError(error)
                }
            }
        } label: {
            HStack(spacing: 8) {
                if viewModel.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(resolvedStyle.submitButton.foregroundColor)
                        .accessibilityHidden(true)
                }

                Text(viewModel.isSubmitting ? "Saving" : configuration.labels.submitButton)
                    .font(resolvedStyle.submitButton.font)
            }
            .frame(maxWidth: .infinity, minHeight: resolvedStyle.submitButton.height)
            .padding(.horizontal, resolvedStyle.submitButton.horizontalPadding)
            .background(
                RoundedRectangle(cornerRadius: resolvedStyle.submitButton.cornerRadius).fill(
                    viewModel.canSubmit
                        ? submitButtonBackgroundColor
                        : resolvedStyle.submitButton.disabledBackgroundColor
                )
            )
            .foregroundStyle(
                viewModel.canSubmit
                    ? resolvedStyle.submitButton.foregroundColor
                    : resolvedStyle.submitButton.disabledForegroundColor
            )
        }
        .buttonStyle(.plain)
        .disabled(!viewModel.canSubmit || viewModel.isSubmitting)
        .accessibilityLabel(viewModel.isSubmitting ? "Saving payment method" : configuration.labels.submitButton)
        .accessibilityValue(PayabliPaymentMethodAccessibility.submitValue(
            canSubmit: viewModel.canSubmit,
            isSubmitting: viewModel.isSubmitting
        ))
        .accessibilityHint(PayabliPaymentMethodAccessibility.submitHint(
            canSubmit: viewModel.canSubmit,
            isSubmitting: viewModel.isSubmitting
        ))
    }

    private func fieldSection(_ section: PayabliPaymentMethodFieldSection) -> some View {
        let groups = fieldGroups(for: section.fields)

        return VStack(alignment: .leading, spacing: section.title == nil ? 0 : resolvedStyle.layout.sectionTitleSpacing) {
            if let title = section.title {
                Text(title)
                    .font(resolvedStyle.sectionTitle.font)
                    .foregroundStyle(resolvedStyle.sectionTitle.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(groups.enumerated()), id: \.offset) { index, group in
                    fieldGroup(
                        group,
                        horizontalSpacing: inputHorizontalSpacing(in: section)
                    )

                    if index < groups.count - 1 {
                        Color.clear
                            .frame(height: verticalSpacing(after: group, in: section))
                            .accessibilityHidden(true)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func fieldGroup(
        _ fields: [PayabliPaymentMethodField],
        horizontalSpacing: CGFloat
    ) -> some View {
        if fields.count == 2 {
            HStack(alignment: .top, spacing: horizontalSpacing) {
                ForEach(fields) { field in
                    fieldView(field)
                }
            }
        } else if let field = fields.first {
            fieldView(field)
        }
    }

    private func inputVerticalSpacing(in section: PayabliPaymentMethodFieldSection) -> CGFloat {
        section.inputVerticalSpacing ?? resolvedStyle.layout.inputVerticalSpacing
    }

    private func inputHorizontalSpacing(in section: PayabliPaymentMethodFieldSection) -> CGFloat {
        section.inputHorizontalSpacing ?? resolvedStyle.layout.inputHorizontalSpacing
    }

    private func verticalSpacing(
        after fields: [PayabliPaymentMethodField],
        in section: PayabliPaymentMethodFieldSection
    ) -> CGFloat {
        for field in fields.reversed() {
            if let spacing = section.fieldVerticalSpacings[field] {
                return spacing
            }
        }

        return inputVerticalSpacing(in: section)
    }

    private func shouldPair(
        _ first: PayabliPaymentMethodField,
        _ second: PayabliPaymentMethodField
    ) -> Bool {
        guard !dynamicTypeSize.isAccessibilitySize else {
            return false
        }

        switch (first, second) {
        case (.cardExpiration, .cardCvv),
             (.cardCvv, .cardExpiration),
             (.firstName, .lastName),
             (.lastName, .firstName):
            return true
        default:
            return false
        }
    }

    @ViewBuilder
    private func fieldView(_ field: PayabliPaymentMethodField) -> some View {
        switch field {
        case .cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip:
            cardFieldView(field)
        case .achHolder, .achRouting, .achAccount, .achAccountType, .achHolderType, .achSecCode, .achDevice:
            achFieldView(field)
        case .methodDescription, .firstName, .lastName, .customerNumber, .billingEmail, .billingZip:
            customerFieldView(field)
        }
    }

    private var cardholderNameBinding: Binding<String> {
        Binding(
            get: { viewModel.cardholderName },
            set: { viewModel.cardholderName = $0 }
        )
    }

    private var focusedFieldBinding: Binding<PayabliPaymentMethodField?> {
        Binding(
            get: { focusedField },
            set: { focusedField = $0 }
        )
    }

    private var cardCvvBinding: Binding<String> {
        Binding(
            get: { viewModel.cardCvv },
            set: { viewModel.cardCvv = $0 }
        )
    }

    private var cardZipBinding: Binding<String> {
        Binding(
            get: { viewModel.cardZip },
            set: { viewModel.cardZip = $0 }
        )
    }

    private var achHolderBinding: Binding<String> {
        Binding(
            get: { viewModel.achHolder },
            set: { viewModel.achHolder = $0 }
        )
    }

    private var achRoutingBinding: Binding<String> {
        Binding(
            get: { viewModel.achRouting },
            set: { viewModel.achRouting = $0 }
        )
    }

    private var achAccountBinding: Binding<String> {
        Binding(
            get: { viewModel.achAccount },
            set: { viewModel.achAccount = $0 }
        )
    }

    private var billingZipBinding: Binding<String> {
        Binding(
            get: { viewModel.billingZip },
            set: { viewModel.billingZip = $0 }
        )
    }

    @ViewBuilder
    private func cardFieldView(_ field: PayabliPaymentMethodField) -> some View {
        switch field {
        case .cardholderName:
            textField(
                field,
                text: cardholderNameBinding,
                textContentType: .name,
                autocapitalization: .words,
                sanitize: viewModel.limitCardholderName
            )
        case .cardNumber:
            cardNumberField()
        case .cardExpiration:
            expirationPickerField()
        case .cardCvv:
            secureField(
                field,
                text: cardCvvBinding,
                keyboardType: .numberPad,
                sanitize: viewModel.limitCardCvv
            )
        case .cardZip:
            textField(
                field,
                text: cardZipBinding,
                keyboardType: .numbersAndPunctuation,
                sanitize: viewModel.limitPostalCode
            )
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func achFieldView(_ field: PayabliPaymentMethodField) -> some View {
        switch field {
        case .achHolder:
            textField(
                field,
                text: achHolderBinding,
                textContentType: .name,
                autocapitalization: .words,
                sanitize: viewModel.limitACHHolderName
            )
        case .achRouting:
            textField(
                field,
                text: achRoutingBinding,
                keyboardType: .numberPad,
                sanitize: viewModel.limitACHRouting
            )
        case .achAccount:
            if configuration.formatting.masksACHAccountEntry {
                secureField(
                    field,
                    text: achAccountBinding,
                    keyboardType: .numberPad,
                    sanitize: viewModel.limitACHAccount
                )
            } else {
                textField(
                    field,
                    text: achAccountBinding,
                    keyboardType: .numberPad,
                    sanitize: viewModel.limitACHAccount
                )
            }
        case .achAccountType:
            pickerField(field, selection: $viewModel.achAccountType, values: PayabliACHAccountType.allCases)
        case .achHolderType:
            pickerField(field, selection: $viewModel.achHolderType, values: PayabliACHHolderType.allCases)
        case .achSecCode:
            pickerField(field, selection: $viewModel.achSecCode, values: PayabliACHSecCode.allCases)
        case .achDevice:
            textField(field, text: $viewModel.achDevice)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func customerFieldView(_ field: PayabliPaymentMethodField) -> some View {
        switch field {
        case .methodDescription:
            textField(field, text: $viewModel.methodDescription, autocapitalization: .sentences)
        case .firstName:
            textField(
                field,
                text: $viewModel.firstName,
                textContentType: .givenName,
                autocapitalization: .words
            )
        case .lastName:
            textField(
                field,
                text: $viewModel.lastName,
                textContentType: .familyName,
                autocapitalization: .words
            )
        case .customerNumber:
            textField(field, text: $viewModel.customerNumber)
        case .billingEmail:
            textField(field, text: $viewModel.billingEmail, keyboardType: .emailAddress, textContentType: .emailAddress)
        case .billingZip:
            textField(
                field,
                text: billingZipBinding,
                keyboardType: .numbersAndPunctuation,
                sanitize: viewModel.limitPostalCode
            )
        default:
            EmptyView()
        }
    }

    private func textField(
        _ field: PayabliPaymentMethodField,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        autocapitalization: UITextAutocapitalizationType = .none,
        sanitize: @escaping (String) -> String = { $0 }
    ) -> some View {
        let label = configuration.labels.label(for: field)
        let inputSize = configuration.inputSizing.size(for: field)

        return fieldRow(field) {
            PayabliPaymentMethodUIKitTextField(
                text: text,
                placeholder: placeholder(for: field),
                field: field,
                focusedField: focusedFieldBinding,
                keyboardType: keyboardType,
                textContentType: textContentType,
                autocapitalization: autocapitalization,
                isSecure: false,
                font: inputUIKitFont,
                textColor: inputUIKitTextColor,
                placeholderColor: inputUIKitPlaceholderColor,
                accessibilityLabel: label,
                sanitize: sanitize
            )
            .padding(.horizontal, inputSize.horizontalPadding)
            .frame(width: inputSize.width)
            .frame(minHeight: inputSize.height)
            .frame(maxWidth: inputSize.width == nil ? .infinity : nil)
            .background(fieldBackground(field))
            .overlay(fieldBorder(field))
            .clipShape(inputShape)
            .privacySensitive()
        }
    }

    private func cardNumberField() -> some View {
        let field = PayabliPaymentMethodField.cardNumber
        let label = configuration.labels.label(for: field)
        let inputSize = configuration.inputSizing.size(for: field)
        let text = Binding(
            get: { viewModel.cardNumber },
            set: { viewModel.cardNumber = $0 }
        )

        return fieldRow(
            field,
            errorMessage: viewModel.cardNumberValidationMessage,
            reservedErrorMessage: showsExternalLabel(for: field) ? "Invalid Card Number" : nil
        ) {
            HStack(spacing: 10) {
                if configuration.cardBrandIconPlacement == .leading {
                    cardBrandIcon
                }

                PayabliPaymentMethodUIKitTextField(
                    text: text,
                    placeholder: placeholder(for: field),
                    field: field,
                    focusedField: focusedFieldBinding,
                    keyboardType: .numberPad,
                    textContentType: .creditCardNumber,
                    autocapitalization: .none,
                    isSecure: false,
                    font: inputUIKitFont,
                    textColor: cardNumberUIKitTextColor,
                    placeholderColor: inputUIKitPlaceholderColor,
                    accessibilityLabel: label,
                    accessibilityHint: PayabliPaymentMethodAccessibility.cardNumberHint(
                        brand: viewModel.detectedCardBrand,
                        validationMessage: viewModel.cardNumberValidationMessage
                    ),
                    sanitize: viewModel.formatCardNumber
                )
                .frame(maxWidth: .infinity, minHeight: inputSize.height, alignment: .leading)

                if configuration.cardBrandIconPlacement == .trailing {
                    cardBrandIcon
                }
            }
            .padding(.horizontal, inputSize.horizontalPadding)
            .frame(width: inputSize.width)
            .frame(minHeight: inputSize.height)
            .frame(maxWidth: inputSize.width == nil ? .infinity : nil)
            .background(fieldBackground(field))
            .overlay(fieldBorder(field))
            .clipShape(inputShape)
            .privacySensitive()
        }
    }

    private func expirationPickerField() -> some View {
        let field = PayabliPaymentMethodField.cardExpiration
        let label = configuration.labels.label(for: field)
        let placeholder = placeholder(for: field, defaultText: "MM/YY")
        let inputSize = configuration.inputSizing.size(for: field)

        return fieldRow(field) {
            Button {
                focusedField = nil
                viewModel.ensureExpirationSelection()
                isExpirationPickerPresented = true
            } label: {
                HStack(spacing: 10) {
                    Text(viewModel.hasSelectedExpiration ? viewModel.expirationDisplayText : placeholder)
                        .font(resolvedStyle.input.font)
                        .foregroundStyle(
                            viewModel.hasSelectedExpiration
                                ? resolvedStyle.input.textColor
                                : resolvedStyle.input.placeholderColor
                        )
                    Spacer(minLength: 8)
                    Image(systemName: "calendar")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(resolvedStyle.input.pickerIconColor)
                }
                .padding(.horizontal, inputSize.horizontalPadding)
                .frame(width: inputSize.width)
                .frame(minHeight: inputSize.height)
                .frame(maxWidth: inputSize.width == nil ? .infinity : nil)
                .background(fieldBackground(nil))
                .overlay(fieldBorder(nil))
                .clipShape(inputShape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(PayabliPaymentMethodAccessibility.expirationValue(
                displayText: viewModel.expirationDisplayText,
                hasSelectedExpiration: viewModel.hasSelectedExpiration
            ))
            .accessibilityHint(PayabliPaymentMethodAccessibility.expirationHint(format: placeholder))
            .accessibilityIdentifier(PayabliPaymentMethodAccessibility.fieldIdentifier(field))
        }
    }

    private var expirationWheelSheet: some View {
        VStack(spacing: 0) {
            HStack {
                Text(configuration.labels.label(for: .cardExpiration))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button("Done") {
                    isExpirationPickerPresented = false
                }
                .font(.body.weight(.semibold))
            }
            .padding(.horizontal, 20)
            .padding(.top, 18)
            .padding(.bottom, 6)

            HStack(spacing: 0) {
                Picker("Month", selection: expirationMonthSelection) {
                    ForEach(1 ... 12, id: \.self) { month in
                        Text(expirationWheelMonthLabel(month))
                            .tag(month)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()

                Picker("Year", selection: expirationYearSelection) {
                    ForEach(expirationYears, id: \.self) { year in
                        Text(String(year))
                            .tag(year)
                    }
                }
                .pickerStyle(.wheel)
                .frame(maxWidth: .infinity)
                .clipped()
            }
            .frame(height: 210)
        }
        .presentationDetents([.height(300)])
        .presentationDragIndicator(.visible)
        .onAppear {
            viewModel.ensureExpirationSelection()
        }
    }

    private var cardBrandIcon: some View {
        let brand = viewModel.detectedCardBrand

        return ZStack {
            RoundedRectangle(cornerRadius: 5)
                .fill(brand.brandAssetName == nil ? Color(uiColor: .tertiarySystemBackground) : .white)
            RoundedRectangle(cornerRadius: 5)
                .stroke(resolvedStyle.input.borderColor.opacity(0.65), lineWidth: 1)

            if let assetName = brand.brandAssetName {
                Image(assetName, bundle: .module)
                    .resizable()
                    .scaledToFit()
                    .padding(.horizontal, 5)
                    .padding(.vertical, 4)
                    .accessibilityHidden(true)
            } else {
                Image(systemName: "creditcard")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(Color(uiColor: .secondaryLabel))
                    .accessibilityHidden(true)
            }
        }
        .frame(width: 42, height: 26)
        .accessibilityHidden(true)
    }

    private func secureField(
        _ field: PayabliPaymentMethodField,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        sanitize: @escaping (String) -> String = { $0 }
    ) -> some View {
        let label = configuration.labels.label(for: field)
        let inputSize = configuration.inputSizing.size(for: field)

        return fieldRow(field) {
            PayabliPaymentMethodUIKitTextField(
                text: text,
                placeholder: placeholder(for: field),
                field: field,
                focusedField: focusedFieldBinding,
                keyboardType: keyboardType,
                autocapitalization: .none,
                isSecure: true,
                font: inputUIKitFont,
                textColor: inputUIKitTextColor,
                placeholderColor: inputUIKitPlaceholderColor,
                accessibilityLabel: label,
                sanitize: sanitize
            )
            .padding(.horizontal, inputSize.horizontalPadding)
            .frame(width: inputSize.width)
            .frame(minHeight: inputSize.height)
            .frame(maxWidth: inputSize.width == nil ? .infinity : nil)
            .background(fieldBackground(field))
            .overlay(fieldBorder(field))
            .clipShape(inputShape)
            .privacySensitive()
        }
    }

    private func pickerField<Value>(
        _ field: PayabliPaymentMethodField,
        selection: Binding<Value>,
        values: [Value]
    ) -> some View where Value: RawRepresentable & Identifiable & Hashable, Value.RawValue == String {
        let label = configuration.labels.label(for: field)
        let inputSize = configuration.inputSizing.size(for: field)

        return fieldRow(field) {
            Menu {
                ForEach(values) { value in
                    Button {
                        selection.wrappedValue = value
                    } label: {
                        if selection.wrappedValue == value {
                            Label(value.rawValue, systemImage: "checkmark")
                        } else {
                            Text(value.rawValue)
                        }
                    }
                }
            } label: {
                HStack(spacing: 10) {
                    Text(selection.wrappedValue.rawValue)
                        .font(resolvedStyle.input.font)
                        .foregroundStyle(resolvedStyle.input.textColor)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(resolvedStyle.input.pickerIconColor)
                }
                .padding(.horizontal, inputSize.horizontalPadding)
                .frame(width: inputSize.width)
                .frame(minHeight: inputSize.height)
                .frame(maxWidth: inputSize.width == nil ? .infinity : nil)
                .background(fieldBackground(nil))
                .overlay(fieldBorder(nil))
                .clipShape(inputShape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(selection.wrappedValue.rawValue)
            .accessibilityHint(PayabliPaymentMethodAccessibility.pickerHint(label: label))
            .accessibilityIdentifier(PayabliPaymentMethodAccessibility.fieldIdentifier(field))
        }
    }

    private func fieldRow(
        _ field: PayabliPaymentMethodField,
        errorMessage: String? = nil,
        reservedErrorMessage: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        let inputSize = configuration.inputSizing.size(for: field)

        return VStack(alignment: .leading, spacing: resolvedStyle.layout.labelSpacing) {
            if showsExternalLabel(for: field) {
                Text(configuration.labels.label(for: field))
                    .font(resolvedStyle.label.font)
                    .foregroundStyle(resolvedStyle.label.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()

            if let errorMessage {
                fieldErrorText(errorMessage, for: field)
            } else if let reservedErrorMessage {
                fieldErrorText(reservedErrorMessage, for: field)
                    .hidden()
                    .accessibilityHidden(true)
            }
        }
        .frame(width: inputSize.width)
        .frame(maxWidth: inputSize.width == nil ? .infinity : nil, alignment: .leading)
    }
}

private extension PayabliPaymentMethodView {
    private func showsExternalLabel(for field: PayabliPaymentMethodField) -> Bool {
        configuration.showsFieldLabels && !configuration.hiddenFieldLabels.contains(field)
    }

    private func placeholder(
        for field: PayabliPaymentMethodField,
        defaultText: String = ""
    ) -> String {
        if let placeholder = configuration.labels.placeholder(for: field) {
            return placeholder
        }
        if configuration.labelLayout == .placeholder {
            return configuration.labels.label(for: field)
        }
        return defaultText
    }

    private func errorText(_ text: String) -> some View {
        return Text(text)
            .font(resolvedStyle.error.font)
            .foregroundStyle(resolvedStyle.error.color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(PayabliPaymentMethodAccessibility.errorLabel(text))
    }

    private func fieldErrorText(
        _ text: String,
        for field: PayabliPaymentMethodField
    ) -> some View {
        let label = configuration.labels.label(for: field)

        return Text(text)
            .font(resolvedStyle.error.font)
            .foregroundStyle(resolvedStyle.error.color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(PayabliPaymentMethodAccessibility.fieldErrorLabel(
                fieldLabel: label,
                message: text
            ))
    }

    private func announceErrorMessage(_ message: String?) {
        guard let announcement = PayabliPaymentMethodAccessibility.errorAnnouncement(for: message) else {
            return
        }

        DispatchQueue.main.async {
            isErrorAccessibilityFocused = true
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    }

    private func announceFieldError(
        field: PayabliPaymentMethodField,
        message: String?
    ) {
        let fieldLabel = configuration.labels.label(for: field)
        guard let announcement = PayabliPaymentMethodAccessibility.fieldErrorAnnouncement(
            fieldLabel: fieldLabel,
            message: message
        ) else {
            return
        }

        UIAccessibility.post(notification: .announcement, argument: announcement)
    }

    private var inputShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: resolvedStyle.input.cornerRadius)
    }

    private var submitButtonBackgroundColor: Color {
        resolvedStyle.submitButton.backgroundColor ?? resolvedStyle.accentColor
    }

    private var focusedInputBackgroundColor: Color {
        resolvedStyle.input.focusedBackgroundColor ?? resolvedStyle.accentColor.opacity(0.05)
    }

    private var focusedInputBorderColor: Color {
        resolvedStyle.input.focusedBorderColor ?? resolvedStyle.accentColor
    }

    private var invalidCardNumberBackgroundColor: Color {
        resolvedStyle.error.color.opacity(0.08)
    }

    private var inputUIKitFont: UIFont {
        resolvedStyle.input.resolvedUIFont
    }

    private var inputUIKitTextColor: UIColor {
        UIColor(resolvedStyle.input.textColor)
    }

    private var inputUIKitPlaceholderColor: UIColor {
        UIColor(resolvedStyle.input.placeholderColor)
    }

    private var cardNumberUIKitTextColor: UIColor {
        viewModel.cardNumberValidationMessage == nil
            ? inputUIKitTextColor
            : UIColor(resolvedStyle.error.color)
    }

    private func fieldBackground(_ field: PayabliPaymentMethodField?) -> some View {
        inputShape.fill(
            fieldHasError(field)
                ? invalidCardNumberBackgroundColor
                : focusedField == field && field != nil
                ? focusedInputBackgroundColor
                : resolvedStyle.input.backgroundColor
        )
    }

    private func fieldBorder(_ field: PayabliPaymentMethodField?) -> some View {
        inputShape.stroke(
            fieldHasError(field)
                ? resolvedStyle.error.color
                : focusedField == field && field != nil
                ? focusedInputBorderColor
                : resolvedStyle.input.borderColor,
            lineWidth: fieldHasError(field)
                ? max(resolvedStyle.input.focusedBorderWidth, resolvedStyle.input.borderWidth)
                : focusedField == field && field != nil
                ? resolvedStyle.input.focusedBorderWidth
                : resolvedStyle.input.borderWidth
        )
    }

    private func fieldHasError(_ field: PayabliPaymentMethodField?) -> Bool {
        field == .cardNumber && viewModel.cardNumberValidationMessage != nil
    }

    private var expirationYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(currentYear ... currentYear + 20)
    }

    private var expirationMonthSelection: Binding<Int> {
        Binding(
            get: {
                viewModel.cardExpirationMonth ?? Calendar.current.component(.month, from: Date())
            },
            set: { month in
                viewModel.selectExpirationMonth(month)
            }
        )
    }

    private var expirationYearSelection: Binding<Int> {
        Binding(
            get: {
                viewModel.cardExpirationYear ?? Calendar.current.component(.year, from: Date())
            },
            set: { year in
                viewModel.selectExpirationYear(year)
            }
        )
    }

    private func expirationWheelMonthLabel(_ month: Int) -> String {
        let shortSymbols = DateFormatter().shortMonthSymbols ?? []
        let name = shortSymbols.indices.contains(month - 1) ? shortSymbols[month - 1] : ""
        return name.isEmpty ? String(format: "%02d", month) : String(format: "%02d %@", month, name)
    }
}

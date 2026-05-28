import PayabliSDKCore
import SwiftUI
import UIKit

public enum PayabliTokenizationField: String, CaseIterable, Identifiable, Sendable {
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

public enum PayabliTokenizationLabelLayout: Sendable {
    case external
    case placeholder
}

public enum PayabliTokenizationCardBrandIconPlacement: Sendable, Equatable {
    case leading
    case trailing
    case hidden
}

public enum PayabliTokenizationErrorMessagePlacement: Sendable, Equatable {
    case top
    case aboveSubmitButton
}

public struct PayabliTokenizationFormatting: Sendable {
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

public struct PayabliTokenizationHiddenValues: Sendable {
    public var cardCvv: String?
    public var achHolderType: PayabliACHHolderType?
    public var achSecCode: PayabliACHSecCode?
    public var achDevice: String?
    public var methodDescription: String?
    public var customerData: PayabliTokenizationCustomerData?

    public init(
        cardCvv: String? = nil,
        achHolderType: PayabliACHHolderType? = nil,
        achSecCode: PayabliACHSecCode? = .web,
        achDevice: String? = nil,
        methodDescription: String? = nil,
        customerData: PayabliTokenizationCustomerData? = nil
    ) {
        self.cardCvv = cardCvv
        self.achHolderType = achHolderType
        self.achSecCode = achSecCode
        self.achDevice = achDevice
        self.methodDescription = methodDescription
        self.customerData = customerData
    }
}

public struct PayabliTokenizationLabels: Sendable {
    public var title: String
    public var subtitle: String?
    public var submitButton: String
    public var fieldLabels: [PayabliTokenizationField: String]

    public init(
        title: String = "Save Payment Method",
        subtitle: String? = nil,
        submitButton: String = "Save",
        fieldLabels: [PayabliTokenizationField: String] = Self.defaultFieldLabels
    ) {
        self.title = title
        self.subtitle = subtitle
        self.submitButton = submitButton
        self.fieldLabels = fieldLabels
    }

    public func label(for field: PayabliTokenizationField) -> String {
        fieldLabels[field] ?? Self.defaultFieldLabels[field] ?? field.rawValue
    }

    public static let defaultFieldLabels: [PayabliTokenizationField: String] = [
        .cardholderName: "Name on card",
        .cardNumber: "Card number",
        .cardExpiration: "Expiration",
        .cardCvv: "CVV",
        .cardZip: "ZIP code",
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
        .billingZip: "Billing ZIP"
    ]
}

public struct PayabliTokenizationInputSize: Sendable, Equatable {
    public var width: CGFloat?
    public var height: CGFloat
    public var horizontalPadding: CGFloat

    public init(
        width: CGFloat? = nil,
        height: CGFloat = 52,
        horizontalPadding: CGFloat = 14
    ) {
        self.width = width
        self.height = max(36, height)
        self.horizontalPadding = max(0, horizontalPadding)
    }
}

public struct PayabliTokenizationInputSizing: Sendable, Equatable {
    public var defaultSize: PayabliTokenizationInputSize
    public var fieldSizes: [PayabliTokenizationField: PayabliTokenizationInputSize]

    public init(
        defaultSize: PayabliTokenizationInputSize = PayabliTokenizationInputSize(),
        fieldSizes: [PayabliTokenizationField: PayabliTokenizationInputSize] = [:]
    ) {
        self.defaultSize = defaultSize
        self.fieldSizes = fieldSizes
    }

    public func size(for field: PayabliTokenizationField) -> PayabliTokenizationInputSize {
        fieldSizes[field] ?? defaultSize
    }
}

public struct PayabliTokenizationFormConfiguration: Sendable {
    public var allowedMethods: [PayabliTokenizationMethod]
    public var defaultMethod: PayabliTokenizationMethod
    public var cardFieldOrder: [PayabliTokenizationField]
    public var achFieldOrder: [PayabliTokenizationField]
    public var hiddenValues: PayabliTokenizationHiddenValues
    public var options: PayabliTokenizationOptions
    public var labels: PayabliTokenizationLabels
    public var labelLayout: PayabliTokenizationLabelLayout
    public var formatting: PayabliTokenizationFormatting
    public var inputSizing: PayabliTokenizationInputSizing
    public var cardBrandIconPlacement: PayabliTokenizationCardBrandIconPlacement
    public var errorMessagePlacement: PayabliTokenizationErrorMessagePlacement

    public init(
        allowedMethods: [PayabliTokenizationMethod] = [.card, .ach],
        defaultMethod: PayabliTokenizationMethod = .card,
        cardFieldOrder: [PayabliTokenizationField] = Self.defaultCardFieldOrder,
        achFieldOrder: [PayabliTokenizationField] = Self.defaultACHFieldOrder,
        hiddenValues: PayabliTokenizationHiddenValues = PayabliTokenizationHiddenValues(),
        options: PayabliTokenizationOptions = PayabliTokenizationOptions(),
        labels: PayabliTokenizationLabels = PayabliTokenizationLabels(),
        labelLayout: PayabliTokenizationLabelLayout = .external,
        formatting: PayabliTokenizationFormatting = PayabliTokenizationFormatting(),
        inputSizing: PayabliTokenizationInputSizing = PayabliTokenizationInputSizing(),
        cardBrandIconPlacement: PayabliTokenizationCardBrandIconPlacement = .trailing,
        errorMessagePlacement: PayabliTokenizationErrorMessagePlacement = .aboveSubmitButton
    ) {
        let methods = allowedMethods.isEmpty ? [defaultMethod] : allowedMethods
        self.allowedMethods = methods
        self.defaultMethod = methods.contains(defaultMethod) ? defaultMethod : methods[0]
        self.cardFieldOrder = Self.includingRequiredFields(
            cardFieldOrder,
            required: Self.requiredCardFields
        )
        self.achFieldOrder = Self.includingRequiredFields(
            Self.visibleACHFields(from: achFieldOrder),
            required: Self.requiredACHFields
        )
        self.hiddenValues = hiddenValues
        self.options = options
        self.labels = labels
        self.labelLayout = labelLayout
        self.formatting = formatting
        self.inputSizing = inputSizing
        self.cardBrandIconPlacement = cardBrandIconPlacement
        self.errorMessagePlacement = errorMessagePlacement
    }

    public static let defaultCardFieldOrder: [PayabliTokenizationField] = [
        .cardholderName,
        .cardNumber,
        .cardExpiration,
        .cardCvv,
        .cardZip
    ]

    public static let defaultACHFieldOrder: [PayabliTokenizationField] = [
        .achHolder,
        .achRouting,
        .achAccount,
        .achAccountType,
        .achHolderType
    ]

    private static let requiredCardFields: [PayabliTokenizationField] = [
        .cardNumber,
        .cardExpiration,
        .cardholderName,
        .cardZip
    ]

    private static let requiredACHFields: [PayabliTokenizationField] = [
        .achHolder,
        .achRouting,
        .achAccount,
        .achAccountType
    ]

    private static func includingRequiredFields(
        _ fields: [PayabliTokenizationField],
        required: [PayabliTokenizationField]
    ) -> [PayabliTokenizationField] {
        fields + required.filter { !fields.contains($0) }
    }

    private static func visibleACHFields(from fields: [PayabliTokenizationField]) -> [PayabliTokenizationField] {
        fields.filter { $0 != .achSecCode }
    }
}

public struct PayabliTokenizationView: View {
    @StateObject private var viewModel: PayabliTokenizationViewModel
    @State private var isExpirationPickerPresented = false
    @FocusState private var focusedField: PayabliTokenizationField?
    @Environment(\.payabliTokenizationStyle) private var environmentStyle
    private let configuration: PayabliTokenizationFormConfiguration
    private let explicitStyle: PayabliTokenizationStyle?
    private let onTokenized: (PayabliTokenizedMethod) -> Void
    private let onError: (Error) -> Void

    @MainActor
    public init(
        component: PayabliTokenization,
        configuration: PayabliTokenizationFormConfiguration = PayabliTokenizationFormConfiguration(),
        style: PayabliTokenizationStyle? = nil,
        onTokenized: @escaping (PayabliTokenizedMethod) -> Void,
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        self.configuration = configuration
        self.explicitStyle = style
        self.onTokenized = onTokenized
        self.onError = onError
        _viewModel = StateObject(wrappedValue: PayabliTokenizationViewModel(
            component: component,
            configuration: configuration
        ))
    }

    private var resolvedStyle: PayabliTokenizationStyle {
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

            VStack(alignment: .leading, spacing: resolvedStyle.layout.fieldGroupSpacing) {
                ForEach(fieldGroups, id: \.self) { group in
                    fieldGroup(group)
                }
            }

            if configuration.errorMessagePlacement == .aboveSubmitButton {
                errorMessageView
            }

            submitButton
        }
        .frame(
            maxWidth: .infinity,
            alignment: .leading
        )
        .privacySensitive()
        .animation(.easeInOut(duration: 0.18), value: viewModel.selectedMethod)
        .sheet(isPresented: $isExpirationPickerPresented) {
            expirationWheelSheet
        }
    }

    @ViewBuilder
    private var errorMessageView: some View {
        if let errorMessage = viewModel.errorMessage {
            Text(errorMessage)
                .font(resolvedStyle.error.font)
                .foregroundStyle(resolvedStyle.error.color)
                .fixedSize(horizontal: false, vertical: true)
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
    }

    private var fieldGroups: [[PayabliTokenizationField]] {
        var groups: [[PayabliTokenizationField]] = []
        var index = viewModel.activeFields.startIndex

        while index < viewModel.activeFields.endIndex {
            let field = viewModel.activeFields[index]
            let nextIndex = viewModel.activeFields.index(after: index)
            if nextIndex < viewModel.activeFields.endIndex {
                let next = viewModel.activeFields[nextIndex]
                if shouldPair(field, next) {
                    groups.append([field, next])
                    index = viewModel.activeFields.index(after: nextIndex)
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
                    onTokenized(result)
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
        .accessibilityHint(viewModel.canSubmit ? "" : "Complete the required fields before saving.")
    }

    @ViewBuilder
    private func fieldGroup(_ fields: [PayabliTokenizationField]) -> some View {
        if fields.count == 2 {
            HStack(alignment: .top, spacing: resolvedStyle.layout.pairedFieldSpacing) {
                ForEach(fields) { field in
                    fieldView(field)
                }
            }
        } else if let field = fields.first {
            fieldView(field)
        }
    }

    private func shouldPair(
        _ first: PayabliTokenizationField,
        _ second: PayabliTokenizationField
    ) -> Bool {
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
    private func fieldView(_ field: PayabliTokenizationField) -> some View {
        switch field {
        case .cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip:
            cardFieldView(field)
        case .achHolder, .achRouting, .achAccount, .achAccountType, .achHolderType, .achSecCode, .achDevice:
            achFieldView(field)
        case .methodDescription, .firstName, .lastName, .customerNumber, .billingEmail, .billingZip:
            customerFieldView(field)
        }
    }

    @ViewBuilder
    private func cardFieldView(_ field: PayabliTokenizationField) -> some View {
        switch field {
        case .cardholderName:
            textField(
                field,
                text: $viewModel.cardholderName,
                textContentType: .name,
                autocapitalization: .words
            )
        case .cardNumber:
            cardNumberField()
        case .cardExpiration:
            expirationPickerField()
        case .cardCvv:
            secureField(
                field,
                text: Binding(
                    get: { viewModel.cardCvv },
                    set: { viewModel.cardCvv = String($0.digitsOnly.prefix(4)) }
                ),
                keyboardType: .numberPad
            )
        case .cardZip:
            textField(field, text: $viewModel.cardZip, keyboardType: .numbersAndPunctuation)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private func achFieldView(_ field: PayabliTokenizationField) -> some View {
        switch field {
        case .achHolder:
            textField(
                field,
                text: $viewModel.achHolder,
                textContentType: .name,
                autocapitalization: .words
            )
        case .achRouting:
            textField(
                field,
                text: Binding(
                    get: { viewModel.achRouting },
                    set: { viewModel.achRouting = String($0.digitsOnly.prefix(9)) }
                ),
                keyboardType: .numberPad
            )
        case .achAccount:
            if configuration.formatting.masksACHAccountEntry {
                secureField(
                    field,
                    text: Binding(
                        get: { viewModel.achAccount },
                        set: { viewModel.achAccount = String($0.digitsOnly.prefix(17)) }
                    ),
                    keyboardType: .numberPad
                )
            } else {
                textField(
                    field,
                    text: Binding(
                        get: { viewModel.achAccount },
                        set: { viewModel.achAccount = String($0.digitsOnly.prefix(17)) }
                    ),
                    keyboardType: .numberPad
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
    private func customerFieldView(_ field: PayabliTokenizationField) -> some View {
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
            textField(field, text: $viewModel.billingZip, keyboardType: .numbersAndPunctuation)
        default:
            EmptyView()
        }
    }

    private func textField(
        _ field: PayabliTokenizationField,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        autocapitalization: TextInputAutocapitalization = .never
    ) -> some View {
        let label = configuration.labels.label(for: field)
        let inputSize = configuration.inputSizing.size(for: field)

        return fieldRow(field) {
            TextField(configuration.labelLayout == .placeholder ? label : "", text: text)
                .keyboardType(keyboardType)
                .textContentType(textContentType)
                .textInputAutocapitalization(autocapitalization)
                .autocorrectionDisabled()
                .focused($focusedField, equals: field)
                .font(resolvedStyle.input.font)
                .foregroundStyle(resolvedStyle.input.textColor)
                .padding(.horizontal, inputSize.horizontalPadding)
                .frame(width: inputSize.width, height: inputSize.height)
                .frame(maxWidth: inputSize.width == nil ? .infinity : nil)
                .background(fieldBackground(field))
                .overlay(fieldBorder(field))
                .clipShape(inputShape)
                .accessibilityLabel(label)
                .privacySensitive()
        }
    }

    private func cardNumberField() -> some View {
        let field = PayabliTokenizationField.cardNumber
        let label = configuration.labels.label(for: field)
        let inputSize = configuration.inputSizing.size(for: field)
        let text = Binding(
            get: { viewModel.cardNumber },
            set: { viewModel.cardNumber = viewModel.formatCardNumber($0) }
        )

        return fieldRow(field, errorMessage: viewModel.cardNumberValidationMessage) {
            HStack(spacing: 10) {
                if configuration.cardBrandIconPlacement == .leading {
                    cardBrandIcon
                }

                TextField(configuration.labelLayout == .placeholder ? label : "", text: text)
                    .keyboardType(.numberPad)
                    .textContentType(.creditCardNumber)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .focused($focusedField, equals: field)
                    .font(resolvedStyle.input.font)
                    .foregroundStyle(cardNumberTextColor)
                    .accessibilityLabel(label)

                if configuration.cardBrandIconPlacement == .trailing {
                    cardBrandIcon
                }
            }
            .padding(.horizontal, inputSize.horizontalPadding)
            .frame(width: inputSize.width, height: inputSize.height)
            .frame(maxWidth: inputSize.width == nil ? .infinity : nil)
            .background(fieldBackground(field))
            .overlay(fieldBorder(field))
            .clipShape(inputShape)
            .privacySensitive()
        }
    }

    private func expirationPickerField() -> some View {
        let field = PayabliTokenizationField.cardExpiration
        let label = configuration.labels.label(for: field)
        let inputSize = configuration.inputSizing.size(for: field)

        return fieldRow(field) {
            Button {
                focusedField = nil
                viewModel.ensureExpirationSelection()
                isExpirationPickerPresented = true
            } label: {
                HStack(spacing: 10) {
                    Text(viewModel.expirationDisplayText)
                        .font(resolvedStyle.input.font)
                        .foregroundStyle(
                            viewModel.hasSelectedExpiration
                                ? resolvedStyle.input.textColor
                                : Color(uiColor: .placeholderText)
                        )
                    Spacer(minLength: 8)
                    Image(systemName: "calendar")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(resolvedStyle.input.pickerIconColor)
                }
                .padding(.horizontal, inputSize.horizontalPadding)
                .frame(width: inputSize.width, height: inputSize.height)
                .frame(maxWidth: inputSize.width == nil ? .infinity : nil)
                .background(fieldBackground(nil))
                .overlay(fieldBorder(nil))
                .clipShape(inputShape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
            .accessibilityValue(viewModel.expirationDisplayText)
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
        .accessibilityLabel(brand.displayName)
    }

    private func secureField(
        _ field: PayabliTokenizationField,
        text: Binding<String>,
        keyboardType: UIKeyboardType = .default
    ) -> some View {
        let label = configuration.labels.label(for: field)
        let inputSize = configuration.inputSizing.size(for: field)

        return fieldRow(field) {
            SecureField(configuration.labelLayout == .placeholder ? label : "", text: text)
                .keyboardType(keyboardType)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused($focusedField, equals: field)
                .font(resolvedStyle.input.font)
                .foregroundStyle(resolvedStyle.input.textColor)
                .padding(.horizontal, inputSize.horizontalPadding)
                .frame(width: inputSize.width, height: inputSize.height)
                .frame(maxWidth: inputSize.width == nil ? .infinity : nil)
                .background(fieldBackground(field))
                .overlay(fieldBorder(field))
                .clipShape(inputShape)
                .accessibilityLabel(label)
                .privacySensitive()
        }
    }

    private func pickerField<Value>(
        _ field: PayabliTokenizationField,
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
                .frame(width: inputSize.width, height: inputSize.height)
                .frame(maxWidth: inputSize.width == nil ? .infinity : nil)
                .background(fieldBackground(nil))
                .overlay(fieldBorder(nil))
                .clipShape(inputShape)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(label)
        }
    }

    private func fieldRow(
        _ field: PayabliTokenizationField,
        errorMessage: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        let inputSize = configuration.inputSizing.size(for: field)

        return VStack(alignment: .leading, spacing: resolvedStyle.layout.labelSpacing) {
            if configuration.labelLayout == .external {
                Text(configuration.labels.label(for: field))
                    .font(resolvedStyle.label.font)
                    .foregroundStyle(resolvedStyle.label.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }

            content()

            if let errorMessage {
                Text(errorMessage)
                    .font(resolvedStyle.error.font)
                    .foregroundStyle(resolvedStyle.error.color)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(width: inputSize.width)
        .frame(maxWidth: inputSize.width == nil ? .infinity : nil, alignment: .leading)
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

    private var cardNumberTextColor: Color {
        viewModel.cardNumberValidationMessage == nil
            ? resolvedStyle.input.textColor
            : resolvedStyle.error.color
    }

    private func fieldBackground(_ field: PayabliTokenizationField?) -> some View {
        inputShape.fill(
            fieldHasError(field)
                ? invalidCardNumberBackgroundColor
                : focusedField == field && field != nil
                ? focusedInputBackgroundColor
                : resolvedStyle.input.backgroundColor
        )
    }

    private func fieldBorder(_ field: PayabliTokenizationField?) -> some View {
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

    private func fieldHasError(_ field: PayabliTokenizationField?) -> Bool {
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

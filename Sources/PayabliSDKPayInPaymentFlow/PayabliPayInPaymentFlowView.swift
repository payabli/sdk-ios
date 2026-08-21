import Foundation
import SwiftUI
import UIKit

// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
public struct PayabliPayInPaymentFlowView: View {
    @StateObject var viewModel: PayabliPayInPaymentFlowViewModel
    @State var isExpirationPickerPresented = false
    @FocusState var focusedField: PayabliPayInPaymentFlowField?
    @AccessibilityFocusState var isErrorAccessibilityFocused: Bool
    @Environment(\.payabliPayInPaymentFlowStyle) var environmentStyle
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    let component: PayabliPayInPaymentFlow
    let configuration: PayabliPayInPaymentFlowFormConfiguration
    let explicitStyle: PayabliPayInPaymentFlowStyle?
    let onCompleted: (PayabliPayInPaymentFlowResult) -> Void
    let onError: (Error) -> Void

    @MainActor
    public init(
        component: PayabliPayInPaymentFlow,
        configuration: PayabliPayInPaymentFlowFormConfiguration = PayabliPayInPaymentFlowFormConfiguration(),
        style: PayabliPayInPaymentFlowStyle? = nil,
        onCompleted: @escaping (PayabliPayInPaymentFlowResult) -> Void,
        onError: @escaping (Error) -> Void = { _ in }
    ) {
        self.component = component
        self.configuration = configuration
        self.explicitStyle = style
        self.onCompleted = onCompleted
        self.onError = onError
        _viewModel = StateObject(wrappedValue: PayabliPayInPaymentFlowViewModel(
            component: component,
            configuration: configuration
        ))
    }

    var resolvedStyle: PayabliPayInPaymentFlowStyle {
        explicitStyle ?? environmentStyle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: resolvedStyle.layout.contentSpacing) {
            header

            if configuration.errorMessagePlacement == .top {
                errorMessageView
            }

            if viewModel.availableMethods.count > 1 {
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
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitive()
        .sheet(isPresented: $isExpirationPickerPresented) {
            expirationWheelSheet
        }
        .onAppear {
            syncViewModelConfiguration()
            viewModel.normalizeSelectedMethodForAvailableMethods()
        }
        .onChange(of: configuration.payabliViewModelSignature) { _ in
            syncViewModelConfiguration()
        }
        .onChange(of: viewModel.availableMethods) { _ in
            viewModel.normalizeSelectedMethodForAvailableMethods()
        }
        .onReceive(component.$operation) { _ in
            syncViewModelConfiguration()
        }
        .onReceive(component.$requestConfiguration) { _ in
            syncViewModelConfiguration()
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
    var errorMessageView: some View {
        if let errorMessage = viewModel.errorMessage {
            errorText(errorMessage)
                .accessibilityFocused($isErrorAccessibilityFocused)
        }
    }

    @ViewBuilder
    var header: some View {
        let title = configuration.labels.title.payabliCaptureTrimmed
        let subtitle = configuration.labels.subtitle?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty

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

    var methodSelector: some View {
        Picker("Payment method", selection: $viewModel.selectedMethod) {
            ForEach(viewModel.availableMethods) { method in
                Text(method.displayName).tag(method)
            }
        }
        .pickerStyle(.segmented)
        .tint(resolvedStyle.accentColor)
        .accessibilityLabel("Payment method")
        .accessibilityValue(viewModel.effectiveSelectedMethod.displayName)
        .accessibilityHint("Selects the payment method type.")
    }

    var activeSections: [PayabliPayInPaymentFlowFieldSection] {
        let sections = switch viewModel.effectiveSelectedMethod {
        case .card:
            configuration.cardSections
        case .ach:
            configuration.achSections
        }
        guard viewModel.component.operation == .storePaymentMethod else {
            return sections
        }
        return sections.compactMap { section in
            let fields = section.fields.filter { !isPaymentSummaryField($0) }
            guard !fields.isEmpty else { return nil }
            return section.replacingFields(fields)
        }
    }

    var submitButton: some View {
        Button {
            Task {
                do {
                    let result = try await viewModel.submit()
                    onCompleted(result)
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

                Text(viewModel.isSubmitting ? "Submitting" : configuration.labels.submitButton)
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
        .accessibilityLabel(viewModel.isSubmitting ? "Submitting payment" : configuration.labels.submitButton)
        .accessibilityHint(viewModel.canSubmit ? "Submits the payment." : "Complete required fields before submitting.")
    }

    func fieldSection(_ section: PayabliPayInPaymentFlowFieldSection) -> some View {
        let groups = fieldGroups(for: section.fields)

        return VStack(alignment: .leading, spacing: section.title == nil ? 0 : resolvedStyle.layout.sectionTitleSpacing) {
            if let title = section.title {
                let titleStyle = section.titleStyle ?? resolvedStyle.sectionTitle

                Text(title)
                    .font(titleStyle.font)
                    .foregroundStyle(titleStyle.color)
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
    func fieldGroup(
        _ fields: [PayabliPayInPaymentFlowField],
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

    @ViewBuilder
    func fieldView(_ field: PayabliPayInPaymentFlowField) -> some View {
        switch field {
        case .cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip:
            cardFieldView(field)
        case .achHolder, .achRouting, .achAccount, .achAccountType, .achHolderType, .achSecCode, .achDevice:
            achFieldView(field)
        case .methodDescription, .firstName, .lastName, .customerNumber, .billingEmail, .billingZip:
            customerFieldView(field)
        case .amount, .serviceFee:
            paymentFieldView(field)
        }
    }

    @ViewBuilder
    func cardFieldView(_ field: PayabliPayInPaymentFlowField) -> some View {
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
                sanitize: viewModel.limitCardCvv
            )
        case .cardZip:
            textField(
                field,
                text: cardZipBinding,
                sanitize: viewModel.limitPostalCode
            )
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    func achFieldView(_ field: PayabliPayInPaymentFlowField) -> some View {
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
            textField(field, text: achRoutingBinding, sanitize: viewModel.limitACHRouting)
        case .achAccount:
            if configuration.formatting.masksACHAccountEntry {
                secureField(field, text: achAccountBinding, sanitize: viewModel.limitACHAccount)
            } else {
                textField(field, text: achAccountBinding, sanitize: viewModel.limitACHAccount)
            }
        case .achAccountType:
            pickerField(field, selection: $viewModel.achAccountType, values: PayabliPayInPaymentFlowACHAccountType.allCases)
        case .achHolderType:
            pickerField(field, selection: $viewModel.achHolderType, values: PayabliPayInPaymentFlowACHHolderType.allCases)
        case .achSecCode:
            pickerField(field, selection: $viewModel.achSecCode, values: PayabliPayInPaymentFlowACHSecCode.allCases)
        case .achDevice:
            textField(field, text: $viewModel.achDevice)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    func customerFieldView(_ field: PayabliPayInPaymentFlowField) -> some View {
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
            textField(field, text: $viewModel.billingEmail, textContentType: .emailAddress)
        case .billingZip:
            textField(
                field,
                text: billingZipBinding,
                sanitize: viewModel.limitPostalCode
            )
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    func paymentFieldView(_ field: PayabliPayInPaymentFlowField) -> some View {
        switch field {
        case .amount, .serviceFee:
            paymentSummaryRow(field)
        default:
            EmptyView()
        }
    }

    func paymentSummaryRow(_ field: PayabliPayInPaymentFlowField) -> some View {
        let labelText = viewModel.paymentSummaryLabelText(for: field)
        let valueText = viewModel.paymentSummaryValueText(for: field)
        let accessibilityText = viewModel.paymentSummaryAccessibilityText(for: field)

        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(labelText)
                .font(configuration.paymentSummary.labelStyle.font)
                .foregroundStyle(configuration.paymentSummary.labelStyle.color)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            Text(valueText)
                .font(configuration.paymentSummary.valueStyle.font)
                .foregroundStyle(configuration.paymentSummary.valueStyle.color)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityIdentifier(fieldIdentifier(field))
    }

    func textField(
        _ field: PayabliPayInPaymentFlowField,
        text: Binding<String>,
        textContentType: UITextContentType? = nil,
        autocapitalization: UITextAutocapitalizationType = .none,
        sanitize: @escaping (String) -> String = { $0 }
    ) -> some View {
        let label = configuration.labels.label(for: field)
        let inputSize = configuration.inputSizing.size(for: field)

        return fieldRow(field) {
            PayabliPayInPaymentFlowUIKitTextField(
                text: text,
                placeholder: placeholder(for: field),
                field: field,
                focusedField: focusedFieldBinding,
                keyboardType: field.keyboardType,
                textContentType: textContentType,
                autocapitalization: autocapitalization,
                isSecure: false,
                font: inputUIKitFont,
                textColor: inputUIKitTextColor,
                placeholderColor: inputUIKitPlaceholderColor,
                accessibilityLabel: label,
                protectsTextContent: true,
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

    func secureField(
        _ field: PayabliPayInPaymentFlowField,
        text: Binding<String>,
        sanitize: @escaping (String) -> String = { $0 }
    ) -> some View {
        let label = configuration.labels.label(for: field)
        let inputSize = configuration.inputSizing.size(for: field)

        return fieldRow(field) {
            PayabliPayInPaymentFlowUIKitTextField(
                text: text,
                placeholder: placeholder(for: field),
                field: field,
                focusedField: focusedFieldBinding,
                keyboardType: field.keyboardType,
                autocapitalization: .none,
                isSecure: true,
                font: inputUIKitFont,
                textColor: inputUIKitTextColor,
                placeholderColor: inputUIKitPlaceholderColor,
                accessibilityLabel: label,
                protectsTextContent: true,
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

    func cardNumberField() -> some View {
        let field = PayabliPayInPaymentFlowField.cardNumber
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

                PayabliPayInPaymentFlowUIKitTextField(
                    text: text,
                    placeholder: placeholder(for: field),
                    field: field,
                    focusedField: focusedFieldBinding,
                    keyboardType: field.keyboardType,
                    textContentType: .creditCardNumber,
                    autocapitalization: .none,
                    isSecure: false,
                    font: inputUIKitFont,
                    textColor: cardNumberUIKitTextColor,
                    placeholderColor: inputUIKitPlaceholderColor,
                    accessibilityLabel: label,
                    accessibilityHint: PayabliPayInPaymentFlowAccessibility.cardNumberHint(
                        brand: viewModel.detectedCardBrand,
                        validationMessage: viewModel.cardNumberValidationMessage
                    ),
                    protectsTextContent: true,
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

    func expirationPickerField() -> some View {
        let field = PayabliPayInPaymentFlowField.cardExpiration
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
            .accessibilityValue(viewModel.hasSelectedExpiration ? viewModel.expirationDisplayText : "No expiration selected")
            .accessibilityHint("Opens month and year selectors.")
            .accessibilityIdentifier(fieldIdentifier(field))
        }
    }

    var expirationWheelSheet: some View {
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
                .accessibilityIdentifier(PayabliPayInPaymentFlowAccessibility.expirationDoneIdentifier)
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

    var cardBrandIcon: some View {
        PayabliPayInPaymentFlowCardBrandIcon(
            brand: viewModel.detectedCardBrand,
            borderColor: resolvedStyle.input.borderColor.opacity(0.65)
        )
    }

    func pickerField<Value>(
        _ field: PayabliPayInPaymentFlowField,
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
            .accessibilityHint("Selects \(label).")
            .accessibilityIdentifier(fieldIdentifier(field))
        }
    }

    func fieldRow(
        _ field: PayabliPayInPaymentFlowField,
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

extension PayabliPayInPaymentFlowView {
    func fieldGroups(for fields: [PayabliPayInPaymentFlowField]) -> [[PayabliPayInPaymentFlowField]] {
        var groups: [[PayabliPayInPaymentFlowField]] = []
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

    func inputVerticalSpacing(in section: PayabliPayInPaymentFlowFieldSection) -> CGFloat {
        section.inputVerticalSpacing ?? resolvedStyle.layout.inputVerticalSpacing
    }

    func inputHorizontalSpacing(in section: PayabliPayInPaymentFlowFieldSection) -> CGFloat {
        section.inputHorizontalSpacing ?? resolvedStyle.layout.inputHorizontalSpacing
    }

    func verticalSpacing(
        after fields: [PayabliPayInPaymentFlowField],
        in section: PayabliPayInPaymentFlowFieldSection
    ) -> CGFloat {
        for field in fields.reversed() {
            if let spacing = section.fieldVerticalSpacings[field] {
                return spacing
            }
        }

        if fields.contains(where: isPaymentSummaryField) {
            return configuration.paymentSummary.rowSpacing
        }

        return inputVerticalSpacing(in: section)
    }

    func shouldPair(
        _ first: PayabliPayInPaymentFlowField,
        _ second: PayabliPayInPaymentFlowField
    ) -> Bool {
        guard !dynamicTypeSize.isAccessibilitySize else { return false }

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

    func isPaymentSummaryField(_ field: PayabliPayInPaymentFlowField) -> Bool {
        field == .amount || field == .serviceFee
    }

    func placeholder(
        for field: PayabliPayInPaymentFlowField,
        defaultText: String? = nil
    ) -> String {
        configuration.labels.placeholder(for: field)
            ?? (configuration.labelLayout == .placeholder ? configuration.labels.label(for: field) : nil)
            ?? defaultText
            ?? ""
    }

    func showsExternalLabel(for field: PayabliPayInPaymentFlowField) -> Bool {
        configuration.showsFieldLabels && !configuration.hiddenFieldLabels.contains(field)
    }

    var focusedInputBackgroundColor: Color {
        resolvedStyle.input.focusedBackgroundColor ?? resolvedStyle.accentColor.opacity(0.05)
    }

    var focusedInputBorderColor: Color {
        resolvedStyle.input.focusedBorderColor ?? resolvedStyle.accentColor
    }

    var invalidCardNumberBackgroundColor: Color {
        resolvedStyle.error.color.opacity(0.08)
    }

    var inputUIKitFont: UIFont {
        resolvedStyle.input.resolvedUIFont
    }

    var inputUIKitTextColor: UIColor {
        UIColor(resolvedStyle.input.textColor)
    }

    var inputUIKitPlaceholderColor: UIColor {
        UIColor(resolvedStyle.input.placeholderColor)
    }

    var cardNumberUIKitTextColor: UIColor {
        viewModel.cardNumberValidationMessage == nil
            ? inputUIKitTextColor
            : UIColor(resolvedStyle.error.color)
    }

    func fieldBackground(_ field: PayabliPayInPaymentFlowField?) -> some ShapeStyle {
        let isFocused = field.map { focusedField == $0 } ?? false
        return fieldHasError(field)
            ? invalidCardNumberBackgroundColor
            : isFocused
            ? focusedInputBackgroundColor
            : resolvedStyle.input.backgroundColor
    }

    func fieldBorder(_ field: PayabliPayInPaymentFlowField?) -> some View {
        let isFocused = field.map { focusedField == $0 } ?? false
        return inputShape.stroke(
            fieldHasError(field)
                ? resolvedStyle.error.color
                : isFocused
                ? focusedInputBorderColor
                : resolvedStyle.input.borderColor,
            lineWidth: fieldHasError(field)
                ? max(resolvedStyle.input.focusedBorderWidth, resolvedStyle.input.borderWidth)
                : isFocused
                ? resolvedStyle.input.focusedBorderWidth
                : resolvedStyle.input.borderWidth
        )
    }

    func fieldHasError(_ field: PayabliPayInPaymentFlowField?) -> Bool {
        field == .cardNumber && viewModel.cardNumberValidationMessage != nil
    }

    var inputShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: resolvedStyle.input.cornerRadius)
    }

    var submitButtonBackgroundColor: Color {
        resolvedStyle.submitButton.backgroundColor ?? resolvedStyle.accentColor
    }

    func errorText(_ message: String) -> some View {
        Text(message)
            .font(resolvedStyle.error.font)
            .foregroundStyle(resolvedStyle.error.color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Payment error")
            .accessibilityValue(message)
    }

    func fieldErrorText(
        _ message: String,
        for field: PayabliPayInPaymentFlowField
    ) -> some View {
        Text(message)
            .font(resolvedStyle.error.font)
            .foregroundStyle(resolvedStyle.error.color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("\(configuration.labels.label(for: field)) error")
            .accessibilityValue(message)
    }

    func fieldIdentifier(_ field: PayabliPayInPaymentFlowField) -> String {
        PayabliPayInPaymentFlowAccessibility.fieldIdentifier(field)
    }

    var cardNumberHint: String {
        if let message = viewModel.cardNumberValidationMessage {
            return message
        }
        return "Detected card brand is \(viewModel.detectedCardBrand.displayName)."
    }

    func sanitizedBinding(
        _ binding: Binding<String>,
        sanitize: @escaping (String) -> String
    ) -> Binding<String> {
        Binding(
            get: { binding.wrappedValue },
            set: { binding.wrappedValue = sanitize($0) }
        )
    }

    var focusedFieldBinding: Binding<PayabliPayInPaymentFlowField?> {
        Binding(
            get: { focusedField },
            set: { focusedField = $0 }
        )
    }

    var cardholderNameBinding: Binding<String> {
        Binding(
            get: { viewModel.cardholderName },
            set: { viewModel.cardholderName = $0 }
        )
    }

    var cardNumberBinding: Binding<String> {
        Binding(
            get: { viewModel.cardNumber },
            set: { viewModel.cardNumber = $0 }
        )
    }

    var cardCvvBinding: Binding<String> {
        Binding(
            get: { viewModel.cardCvv },
            set: { viewModel.cardCvv = $0 }
        )
    }

    var cardZipBinding: Binding<String> {
        Binding(
            get: { viewModel.cardZip },
            set: { viewModel.cardZip = $0 }
        )
    }

    var achHolderBinding: Binding<String> {
        Binding(
            get: { viewModel.achHolder },
            set: { viewModel.achHolder = $0 }
        )
    }

    var achRoutingBinding: Binding<String> {
        Binding(
            get: { viewModel.achRouting },
            set: { viewModel.achRouting = $0 }
        )
    }

    var achAccountBinding: Binding<String> {
        Binding(
            get: { viewModel.achAccount },
            set: { viewModel.achAccount = $0 }
        )
    }

    var billingZipBinding: Binding<String> {
        Binding(
            get: { viewModel.billingZip },
            set: { viewModel.billingZip = $0 }
        )
    }

    var expirationMonthSelection: Binding<Int> {
        Binding(
            get: { viewModel.cardExpirationMonth ?? Calendar.current.component(.month, from: Date()) },
            set: { viewModel.selectExpirationMonth($0) }
        )
    }

    var expirationYearSelection: Binding<Int> {
        Binding(
            get: { viewModel.cardExpirationYear ?? Calendar.current.component(.year, from: Date()) },
            set: { viewModel.selectExpirationYear($0) }
        )
    }

    var expirationYears: [Int] {
        let current = Calendar.current.component(.year, from: Date())
        return Array(current ... current + 20)
    }

    func expirationWheelMonthLabel(_ month: Int) -> String {
        String(format: "%02d", month)
    }

    func announceErrorMessage(_ message: String?) {
        guard let message else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
        isErrorAccessibilityFocused = true
    }

    func announceFieldError(
        field: PayabliPayInPaymentFlowField,
        message: String?
    ) {
        guard let message else { return }
        UIAccessibility.post(
            notification: .announcement,
            argument: "\(configuration.labels.label(for: field)): \(message)"
        )
    }

    func syncViewModelConfiguration() {
        viewModel.update(
            component: component,
            configuration: configuration
        )
    }
}

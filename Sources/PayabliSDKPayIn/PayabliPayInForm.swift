import Foundation
import PayabliSDKCore
import SwiftUI
import UIKit

/// The outcome of one submission the form sent.
public enum PayabliPayInFormSuccess {
    /// The transaction the operation completed.
    case payment(PayabliPayInResult)
    /// The payment method the operation stored.
    case method(PayabliPayInStoredMethod)

    init(_ result: PayabliPayInResult) {
        if let storedMethod = result.storedPaymentMethod, result.kind == .storedPaymentMethod {
            self = .method(storedMethod)
        } else {
            self = .payment(result)
        }
    }
}

// swiftlint:disable file_length
// swiftlint:disable:next type_body_length
public struct PayabliPayInForm: View {
    @StateObject var viewModel: PayabliPayInViewModel
    @State var isExpirationPickerPresented = false
    @FocusState var focusedField: PayabliPayInField?
    @AccessibilityFocusState var isFailureMessageAccessibilityFocused: Bool
    @Environment(\.payabliPayInStyle) var environmentStyle
    @Environment(\.dynamicTypeSize) var dynamicTypeSize

    let payIn: PayabliPayIn
    let operation: PayabliPayInOperation
    let configuration: PayabliPayInFormConfiguration
    let labels: PayabliPayInFormLabels
    let explicitStyle: PayabliPayInFormStyle?
    let onCompleted: (PayabliPayInFormSuccess) -> Void
    let onFailed: (any PayabliError) -> Void
    let onMethodChanged: (PayabliPayInMethodType) -> Void

    /// Creates the form, bound to one operation of a component.
    ///
    /// - Parameters:
    ///   - payIn: the component the form submits through.
    ///   - operation: the one operation the form submits.
    ///   - configuration: the fields the form draws and how they behave.
    ///   - labels: the wording the form draws; what is absent or blank falls back to the SDK's own.
    ///   - style: the colors, fonts and spacing the form draws with, nil to read the environment's.
    ///   - onCompleted: called once with the outcome of the submission: `.method` for a stored payment
    ///     method, `.payment` for a transaction.
    ///   - onFailed: called with the failure the flow threw, unchanged, when a submission the form
    ///     sent did not complete.
    ///   - onMethodChanged: called when the drawn method changes: the payer's choice, or the
    ///     configuration withdrawing the method the payer had chosen. Not called for the method the
    ///     form opens with.
    @MainActor
    public init(
        payIn: PayabliPayIn,
        operation: PayabliPayInOperation,
        configuration: PayabliPayInFormConfiguration = PayabliPayInFormConfiguration(),
        labels: PayabliPayInFormLabels = PayabliPayInFormLabels(),
        style: PayabliPayInFormStyle? = nil,
        onCompleted: @escaping (PayabliPayInFormSuccess) -> Void,
        onFailed: @escaping (any PayabliError) -> Void,
        onMethodChanged: @escaping (PayabliPayInMethodType) -> Void
    ) {
        self.payIn = payIn
        self.operation = operation
        self.configuration = configuration
        self.labels = labels
        self.explicitStyle = style
        self.onCompleted = onCompleted
        self.onFailed = onFailed
        self.onMethodChanged = onMethodChanged
        _viewModel = StateObject(wrappedValue: PayabliPayInViewModel(
            component: payIn,
            operation: operation,
            configuration: configuration,
            labels: labels
        ))
    }

    var resolvedStyle: PayabliPayInFormStyle {
        explicitStyle ?? environmentStyle
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: resolvedStyle.layout.contentSpacing) {
            header

            if configuration.failureMessagePlacement == .top {
                failureMessageView
            }

            if viewModel.availableMethods.count > 1 {
                methodSelector
            }

            VStack(alignment: .leading, spacing: resolvedStyle.layout.sectionSpacing) {
                ForEach(Array(drawnSections.enumerated()), id: \.offset) { _, drawn in
                    if drawn.isSummary {
                        summarySection(drawn)
                    } else {
                        fieldSection(drawn.section)
                    }
                }
            }

            if configuration.failureMessagePlacement == .aboveSubmitButton {
                failureMessageView
            }

            submitButton
        }
        .transaction { transaction in
            transaction.animation = nil
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .privacySensitive()
        // Read-only while a submission is in flight: a refusal applies to the state that was
        // submitted, and an edit after the request left would mark a value it never saw.
        .disabled(viewModel.isSubmitting)
        .sheet(isPresented: $isExpirationPickerPresented) {
            expirationWheelSheet
        }
        .onAppear {
            syncViewModel()
            viewModel.normalizeSelectedMethodForAvailableMethods()
        }
        .onChange(of: PayInPaymentFlowConfigurationChange(configuration, labels: labels)) { change in
            viewModel.update(
                component: payIn,
                operation: operation,
                configuration: change.configuration,
                labels: change.labels
            )
        }
        .onChange(of: operation) { _ in
            syncViewModel()
        }
        .onChange(of: viewModel.availableMethods) { _ in
            viewModel.normalizeSelectedMethodForAvailableMethods()
        }
        .onChange(of: viewModel.selectedMethod) { method in
            onMethodChanged(method)
        }
        .onReceive(payIn.$requestConfiguration) { _ in
            syncViewModel()
        }
        .onChange(of: viewModel.failureMessage) { message in
            announceFailureMessage(message)
        }
        .onChange(of: viewModel.rejectedFields) { [marked = viewModel.rejectedFields] rejected in
            announceRejectedFields(rejected.subtracting(marked))
        }
        .onChange(of: viewModel.cardNumberValidationMessage) { message in
            announceFieldError(
                field: .cardNumber,
                message: message
            )
        }
    }

    @ViewBuilder
    var failureMessageView: some View {
        if let failureMessage = viewModel.failureMessage {
            errorText(failureMessage)
                .accessibilityFocused($isFailureMessageAccessibilityFocused)
        }
    }

    @ViewBuilder
    var header: some View {
        let title = labels.drawnTitle
        let subtitle = labels.subtitle?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty

        if title != nil || subtitle != nil {
            VStack(alignment: .leading, spacing: resolvedStyle.layout.headerSpacing) {
                if let title {
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

    var drawnSections: [PayInDrawnSection] {
        let sections = switch viewModel.effectiveSelectedMethod {
        case .card:
            configuration.cardSections
        case .bankAccount:
            configuration.bankSections
        }
        let charges = viewModel.operation != .storePaymentMethod
        return PayInSummaryPlacement.place(
            sections,
            paymentDetails: charges ? payIn.requestConfiguration?.paymentDetails : nil,
            showsBaseAmount: configuration.showsBaseAmount
        )
    }

    var submitButton: some View {
        Button {
            submitForOutcome()
        } label: {
            HStack(spacing: 8) {
                if viewModel.isSubmitting {
                    ProgressView()
                        .controlSize(.small)
                        .tint(resolvedStyle.submitButton.foregroundColor)
                        .accessibilityHidden(true)
                }

                Text(submitButtonText)
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
        .accessibilityLabel(submitButtonText)
        .accessibilityHint(submitAccessibilityHint)
    }

    /// Sends the filled form through its operation and reports the outcome to the host.
    @MainActor
    func submitForOutcome() {
        Task {
            do {
                let result = try await viewModel.submit()
                onCompleted(PayabliPayInFormSuccess(result))
            } catch let error as any PayabliError {
                onFailed(error)
            } catch {
                onFailed(Self.reportedUnexpectedFailure(error))
            }
        }
    }

    /// The failure reported for an error the SDK does not name: the catalog's reason, the failing
    /// type's name, its message never.
    static func reportedUnexpectedFailure(_ error: any Error) -> PayabliGenericError {
        PayabliGenericError(
            type: .unknown,
            reason: PayabliErrorType.unknown.message,
            detail: nil,
            underlying: RedactedCause(error)
        )
    }

    func fieldSection(_ section: PayabliPayInFieldSection) -> some View {
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
        _ fields: [PayabliPayInField],
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
    func fieldView(_ field: PayabliPayInField) -> some View {
        switch field {
        case .cardholderName, .cardNumber, .cardExpiration, .cardCvv, .cardZip:
            cardFieldView(field)
        case .accountHolder, .routingNumber, .accountNumber, .accountType, .accountHolderType, .secCode, .deviceId:
            achFieldView(field)
        case .methodDescription, .firstName, .lastName, .customerNumber, .billingEmail, .billingZip:
            customerFieldView(field)
        case .amount, .serviceFee, .surchargeFee:
            EmptyView()
        }
    }

    @ViewBuilder
    func cardFieldView(_ field: PayabliPayInField) -> some View {
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
    func achFieldView(_ field: PayabliPayInField) -> some View {
        switch field {
        case .accountHolder:
            textField(
                field,
                text: achHolderBinding,
                textContentType: .name,
                autocapitalization: .words,
                sanitize: viewModel.limitAccountHolderName
            )
        case .routingNumber:
            textField(field, text: achRoutingBinding, sanitize: viewModel.limitRoutingNumber)
        case .accountNumber:
            if configuration.formatting.masksAccountNumber {
                secureField(field, text: achAccountBinding, sanitize: viewModel.limitAccountNumber)
            } else {
                textField(field, text: achAccountBinding, sanitize: viewModel.limitAccountNumber)
            }
        case .accountType:
            pickerField(field, selection: $viewModel.accountType, values: PayabliPayInAccountType.allCases)
        case .accountHolderType:
            pickerField(field, selection: $viewModel.accountHolderType, values: PayabliPayInAccountHolderType.allCases)
        case .secCode:
            pickerField(field, selection: $viewModel.secCode, values: PayabliPayInSecCode.allCases)
        case .deviceId:
            textField(field, text: $viewModel.deviceId)
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    func customerFieldView(_ field: PayabliPayInField) -> some View {
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

    func summarySection(_ drawn: PayInDrawnSection) -> some View {
        let summary = configuration.paymentSummary
        let currency = payIn.requestConfiguration?.paymentDetails.currency

        return VStack(alignment: .leading, spacing: drawn.title == nil ? 0 : resolvedStyle.layout.sectionTitleSpacing) {
            if let title = drawn.title {
                let titleStyle = drawn.section.titleStyle ?? resolvedStyle.sectionTitle

                Text(title)
                    .font(titleStyle.font)
                    .foregroundStyle(titleStyle.color)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
            }

            VStack(alignment: .leading, spacing: summary.rowSpacing) {
                ForEach(drawn.rows, id: \.field) { row in
                    summaryRow(
                        label: PayabliPayInSummaryRows.labelText(for: row.field, labels: labels),
                        value: PayabliPayInSummaryRows.formattedAmount(row.amount, currency: currency),
                        identifier: fieldIdentifier(row.field)
                    )
                }

                if let total = drawn.total {
                    summaryRow(
                        label: PayabliPayInSummaryRows.totalLabelText(labels: labels),
                        value: PayabliPayInSummaryRows.formattedAmount(total, currency: currency),
                        identifier: PayabliPayInAccessibility.totalIdentifier
                    )
                }
            }
        }
    }

    func summaryRow(label: String, value: String, identifier: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(label)
                .font(configuration.paymentSummary.labelStyle.font)
                .foregroundStyle(configuration.paymentSummary.labelStyle.color)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 12)

            Text(value)
                .font(configuration.paymentSummary.valueStyle.font)
                .foregroundStyle(configuration.paymentSummary.valueStyle.color)
                .multilineTextAlignment(.trailing)
                .fixedSize(horizontal: false, vertical: true)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) \(value)")
        .accessibilityIdentifier(identifier)
    }

    func textField(
        _ field: PayabliPayInField,
        text: Binding<String>,
        textContentType: UITextContentType? = nil,
        autocapitalization: UITextAutocapitalizationType = .none,
        sanitize: @escaping (String) -> String = { $0 }
    ) -> some View {
        let label = labels.label(for: field)
        let inputSize = configuration.inputSizing.size(for: field)

        return fieldRow(field) {
            PayabliPayInUIKitTextField(
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
        _ field: PayabliPayInField,
        text: Binding<String>,
        sanitize: @escaping (String) -> String = { $0 }
    ) -> some View {
        let label = labels.label(for: field)
        let inputSize = configuration.inputSizing.size(for: field)

        return fieldRow(field) {
            PayabliPayInUIKitTextField(
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
        let field = PayabliPayInField.cardNumber
        let label = labels.label(for: field)
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

                PayabliPayInUIKitTextField(
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
                    accessibilityHint: PayabliPayInAccessibility.cardNumberHint(
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
        let field = PayabliPayInField.cardExpiration
        let label = labels.label(for: field)
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
                .background(fieldBackground(field))
                .overlay(fieldBorder(field))
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
                Text(labels.label(for: .cardExpiration))
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                Button("Done") {
                    isExpirationPickerPresented = false
                }
                .font(.body.weight(.semibold))
                .accessibilityIdentifier(PayabliPayInAccessibility.expirationDoneIdentifier)
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
        PayabliPayInCardBrandIcon(
            brand: viewModel.detectedCardBrand,
            borderColor: resolvedStyle.input.borderColor.opacity(0.65)
        )
    }

    func pickerField<Value>(
        _ field: PayabliPayInField,
        selection: Binding<Value>,
        values: [Value]
    ) -> some View where Value: RawRepresentable & Identifiable & Hashable, Value.RawValue == String {
        let label = labels.label(for: field)
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
                .background(fieldBackground(field))
                .overlay(fieldBorder(field))
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
        _ field: PayabliPayInField,
        errorMessage: String? = nil,
        reservedErrorMessage: String? = nil,
        @ViewBuilder content: () -> some View
    ) -> some View {
        let inputSize = configuration.inputSizing.size(for: field)

        return VStack(alignment: .leading, spacing: resolvedStyle.layout.labelSpacing) {
            if showsExternalLabel(for: field) {
                Text(labels.label(for: field))
                    .font(resolvedStyle.label.font)
                    .foregroundStyle(resolvedStyle.label.color)
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()

            if let errorMessage = errorMessage ?? rejectedMessage(for: field) {
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

extension PayabliPayInForm {
    func fieldGroups(for fields: [PayabliPayInField]) -> [[PayabliPayInField]] {
        var groups: [[PayabliPayInField]] = []
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

    func inputVerticalSpacing(in section: PayabliPayInFieldSection) -> CGFloat {
        section.inputVerticalSpacing ?? resolvedStyle.layout.inputVerticalSpacing
    }

    func inputHorizontalSpacing(in section: PayabliPayInFieldSection) -> CGFloat {
        section.inputHorizontalSpacing ?? resolvedStyle.layout.inputHorizontalSpacing
    }

    func verticalSpacing(
        after fields: [PayabliPayInField],
        in section: PayabliPayInFieldSection
    ) -> CGFloat {
        for field in fields.reversed() {
            if let spacing = section.fieldVerticalSpacings[field] {
                return spacing
            }
        }

        return inputVerticalSpacing(in: section)
    }

    func shouldPair(
        _ first: PayabliPayInField,
        _ second: PayabliPayInField
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

    func placeholder(
        for field: PayabliPayInField,
        defaultText: String? = nil
    ) -> String {
        labels.placeholder(for: field)
            ?? (configuration.labelLayout == .placeholder ? labels.label(for: field) : nil)
            ?? defaultText
            ?? ""
    }

    func showsExternalLabel(for field: PayabliPayInField) -> Bool {
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

    func fieldBackground(_ field: PayabliPayInField?) -> Color {
        if fieldHasError(field) {
            return invalidCardNumberBackgroundColor
        }
        if isFocused(field) {
            return focusedInputBackgroundColor
        }
        return resolvedStyle.input.backgroundColor
    }

    func fieldBorder(_ field: PayabliPayInField?) -> some View {
        inputShape.stroke(
            fieldBorderColor(field),
            lineWidth: fieldBorderWidth(field)
        )
    }

    func fieldBorderColor(_ field: PayabliPayInField?) -> Color {
        if fieldHasError(field) {
            return resolvedStyle.error.color
        }
        if isFocused(field) {
            return focusedInputBorderColor
        }
        return resolvedStyle.input.borderColor
    }

    func fieldBorderWidth(_ field: PayabliPayInField?) -> CGFloat {
        if fieldHasError(field) {
            return max(resolvedStyle.input.focusedBorderWidth, resolvedStyle.input.borderWidth)
        }
        if isFocused(field) {
            return resolvedStyle.input.focusedBorderWidth
        }
        return resolvedStyle.input.borderWidth
    }

    func isFocused(_ field: PayabliPayInField?) -> Bool {
        field.map { focusedField == $0 } ?? false
    }

    func fieldHasError(_ field: PayabliPayInField?) -> Bool {
        guard let field else { return false }
        return (field == .cardNumber && viewModel.cardNumberValidationMessage != nil)
            || viewModel.rejectedFields.contains(field)
    }

    /// The mark's own text, which a screen reader hears once when the mark appears and again on the field.
    ///
    /// - Parameter field: the field the refusal marked.
    /// - Returns: the mark's text, or nil when the field is not marked.
    func rejectedMessage(for field: PayabliPayInField) -> String? {
        viewModel.rejectedFields.contains(field) ? PayabliPayInAccessibility.rejectedFieldMessage : nil
    }

    var submitAccessibilityHint: String {
        PayabliPayInAccessibility.submitHint(
            canSubmit: viewModel.canSubmit,
            hasMarkedField: viewModel.hasMarkedFieldOnScreen
        )
    }

    var inputShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: resolvedStyle.input.cornerRadius)
    }

    var submitButtonText: String {
        PayInSubmitWording.text(
            showing: viewModel.operation,
            submitting: viewModel.submittingOperation,
            hostWording: labels.hostSubmitButton
        )
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
        for field: PayabliPayInField
    ) -> some View {
        Text(message)
            .font(resolvedStyle.error.font)
            .foregroundStyle(resolvedStyle.error.color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("\(labels.label(for: field)) error")
            .accessibilityValue(message)
    }

    func fieldIdentifier(_ field: PayabliPayInField) -> String {
        PayabliPayInAccessibility.fieldIdentifier(field)
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

    var focusedFieldBinding: Binding<PayabliPayInField?> {
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
            get: { viewModel.accountHolder },
            set: { viewModel.accountHolder = $0 }
        )
    }

    var achRoutingBinding: Binding<String> {
        Binding(
            get: { viewModel.routingNumber },
            set: { viewModel.routingNumber = $0 }
        )
    }

    var achAccountBinding: Binding<String> {
        Binding(
            get: { viewModel.accountNumber },
            set: { viewModel.accountNumber = $0 }
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

    func announceFailureMessage(_ message: String?) {
        guard let message else { return }
        UIAccessibility.post(notification: .announcement, argument: message)
        isFailureMessageAccessibilityFocused = true
    }

    /// Announces the fields a refusal has just marked, in the order the form draws them.
    ///
    /// - Parameter newlyMarked: The fields marked by this refusal and not before it.
    func announceRejectedFields(_ newlyMarked: Set<PayabliPayInField>) {
        guard let announcement = PayabliPayInAccessibility.rejectedFieldsAnnouncement(
            newlyMarked: newlyMarked,
            drawnFields: viewModel.activeFields,
            label: labels.label(for:),
            message: PayabliPayInAccessibility.rejectedFieldMessage
        ) else { return }
        UIAccessibility.post(notification: .announcement, argument: announcement)
    }

    func announceFieldError(
        field: PayabliPayInField,
        message: String?
    ) {
        guard let message else { return }
        UIAccessibility.post(
            notification: .announcement,
            argument: "\(labels.label(for: field)): \(message)"
        )
    }

    func syncViewModel() {
        viewModel.update(
            component: payIn,
            operation: operation,
            configuration: configuration,
            labels: labels
        )
    }
}

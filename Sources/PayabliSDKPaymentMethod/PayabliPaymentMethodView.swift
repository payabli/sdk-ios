import PayabliSDKCore
import SwiftUI
import UIKit

public struct PayabliPaymentMethodView: View {
    @StateObject var viewModel: PayabliPaymentMethodViewModel
    @State var isExpirationPickerPresented = false
    @FocusState var focusedField: PayabliPaymentMethodField?
    @AccessibilityFocusState var isErrorAccessibilityFocused: Bool
    @Environment(\.payabliPaymentMethodStyle) var environmentStyle
    @Environment(\.dynamicTypeSize) var dynamicTypeSize
    let configuration: PayabliPaymentMethodFormConfiguration
    let explicitStyle: PayabliPaymentMethodStyle?
    let onPaymentMethodAdded: (PayabliStoredPaymentMethod) -> Void
    let onError: (Error) -> Void

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

    var resolvedStyle: PayabliPaymentMethodStyle {
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
    var errorMessageView: some View {
        if let errorMessage = viewModel.errorMessage {
            errorText(errorMessage)
                .accessibilityFocused($isErrorAccessibilityFocused)
        }
    }

    @ViewBuilder
    var header: some View {
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

    var methodSelector: some View {
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

    var activeSections: [PayabliPaymentMethodFieldSection] {
        switch viewModel.selectedMethod {
        case .card:
            return configuration.cardSections
        case .ach:
            return configuration.achSections
        }
    }

    func fieldGroups(
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

    var submitButton: some View {
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
}

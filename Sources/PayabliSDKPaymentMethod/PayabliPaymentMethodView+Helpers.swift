import PayabliSDKCore
import SwiftUI
import UIKit

extension PayabliPaymentMethodView {
    func showsExternalLabel(for field: PayabliPaymentMethodField) -> Bool {
        configuration.showsFieldLabels && !configuration.hiddenFieldLabels.contains(field)
    }

    func placeholder(
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

    func errorText(_ text: String) -> some View {
        return Text(text)
            .font(resolvedStyle.error.font)
            .foregroundStyle(resolvedStyle.error.color)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(PayabliPaymentMethodAccessibility.errorLabel(text))
    }

    func fieldErrorText(
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

    func announceErrorMessage(_ message: String?) {
        guard let announcement = PayabliPaymentMethodAccessibility.errorAnnouncement(for: message) else {
            return
        }

        DispatchQueue.main.async {
            isErrorAccessibilityFocused = true
            UIAccessibility.post(notification: .announcement, argument: announcement)
        }
    }

    func announceFieldError(
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

    var inputShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: resolvedStyle.input.cornerRadius)
    }

    var submitButtonBackgroundColor: Color {
        resolvedStyle.submitButton.backgroundColor ?? resolvedStyle.accentColor
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

    func fieldBackground(_ field: PayabliPaymentMethodField?) -> some View {
        inputShape.fill(
            fieldHasError(field)
                ? invalidCardNumberBackgroundColor
                : focusedField == field && field != nil
                ? focusedInputBackgroundColor
                : resolvedStyle.input.backgroundColor
        )
    }

    func fieldBorder(_ field: PayabliPaymentMethodField?) -> some View {
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

    func fieldHasError(_ field: PayabliPaymentMethodField?) -> Bool {
        field == .cardNumber && viewModel.cardNumberValidationMessage != nil
    }

    var expirationYears: [Int] {
        let currentYear = Calendar.current.component(.year, from: Date())
        return Array(currentYear ... currentYear + 20)
    }

    var expirationMonthSelection: Binding<Int> {
        Binding(
            get: {
                viewModel.cardExpirationMonth ?? Calendar.current.component(.month, from: Date())
            },
            set: { month in
                viewModel.selectExpirationMonth(month)
            }
        )
    }

    var expirationYearSelection: Binding<Int> {
        Binding(
            get: {
                viewModel.cardExpirationYear ?? Calendar.current.component(.year, from: Date())
            },
            set: { year in
                viewModel.selectExpirationYear(year)
            }
        )
    }

    func expirationWheelMonthLabel(_ month: Int) -> String {
        let shortSymbols = DateFormatter().shortMonthSymbols ?? []
        let name = shortSymbols.indices.contains(month - 1) ? shortSymbols[month - 1] : ""
        return name.isEmpty ? String(format: "%02d", month) : String(format: "%02d %@", month, name)
    }
}

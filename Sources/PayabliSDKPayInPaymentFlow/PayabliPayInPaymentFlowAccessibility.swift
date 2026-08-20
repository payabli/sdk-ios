import CoreGraphics

enum PayabliPayInPaymentFlowAccessibility {
    static let minimumTouchTarget: CGFloat = 44

    static func fieldIdentifier(_ field: PayabliPayInPaymentFlowField) -> String {
        "payabli.payInPaymentFlow.field.\(field.rawValue)"
    }

    /// The control that accepts the expiry wheel. Every field in that view can be
    /// addressed by identifier and this button could only be found by its title,
    /// which is a visible string and the one thing a caller should not depend on.
    static let expirationDoneIdentifier = "payabli.payInPaymentFlow.control.expirationDone"

    /// The Done item on the accessory a keyboard with no return key carries. The
    /// title comes from UIKit and arrives translated, so it is not what a caller
    /// should aim at.
    static let keyboardDoneIdentifier = "payabli.payInPaymentFlow.control.keyboardDone"

    static func textFieldValue(
        text: String,
        isSecure: Bool
    ) -> String {
        let value = text.trimmed
        guard !value.isEmpty else { return "Empty" }
        return isSecure ? "Entered" : value
    }

    static func expirationValue(
        displayText: String,
        hasSelectedExpiration: Bool
    ) -> String {
        hasSelectedExpiration ? displayText : "No expiration selected"
    }

    static func expirationHint(format: String) -> String {
        "Opens month and year picker. Expected format \(format)."
    }

    static func pickerHint(label: String) -> String {
        "Opens \(label.lowercased()) options."
    }

    static func submitHint(
        canSubmit: Bool,
        isSubmitting: Bool
    ) -> String {
        if isSubmitting {
            return "Saving payment method."
        }
        return canSubmit
            ? "Saves the payment method."
            : "Complete the required fields before saving."
    }

    static func submitValue(
        canSubmit: Bool,
        isSubmitting: Bool
    ) -> String {
        if isSubmitting {
            return "In progress"
        }
        return canSubmit ? "" : "Disabled"
    }

    static func cardNumberHint(
        brand: PayabliPayInPaymentFlowCardBrand,
        validationMessage: String?
    ) -> String? {
        var parts: [String] = []
        if brand != .unknown {
            parts.append("\(brand.displayName) detected.")
        }
        if let validationMessage {
            parts.append("Error: \(validationMessage).")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }

    static func errorLabel(_ message: String) -> String {
        "Error: \(message)"
    }

    static func fieldErrorLabel(
        fieldLabel: String,
        message: String
    ) -> String {
        "Error in \(fieldLabel): \(message)"
    }

    static func errorAnnouncement(for message: String?) -> String? {
        guard let message = message?.trimmed.nilIfEmpty else { return nil }
        return errorLabel(message)
    }

    static func fieldErrorAnnouncement(
        fieldLabel: String,
        message: String?
    ) -> String? {
        guard let message = message?.trimmed.nilIfEmpty else { return nil }
        return fieldErrorLabel(fieldLabel: fieldLabel, message: message)
    }
}

import SwiftUI
import UIKit

struct PayabliPaymentMethodUIKitTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var field: PayabliPaymentMethodField
    @Binding var focusedField: PayabliPaymentMethodField?
    var keyboardType: UIKeyboardType
    var textContentType: UITextContentType?
    var autocapitalization: UITextAutocapitalizationType
    var isSecure: Bool
    var textColor: UIColor
    var sanitize: (String) -> String

    init(
        text: Binding<String>,
        placeholder: String,
        field: PayabliPaymentMethodField,
        focusedField: Binding<PayabliPaymentMethodField?>,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        autocapitalization: UITextAutocapitalizationType = .none,
        isSecure: Bool = false,
        textColor: UIColor = .label,
        sanitize: @escaping (String) -> String = { $0 }
    ) {
        _text = text
        self.placeholder = placeholder
        self.field = field
        _focusedField = focusedField
        self.keyboardType = keyboardType
        self.textContentType = textContentType
        self.autocapitalization = autocapitalization
        self.isSecure = isSecure
        self.textColor = textColor
        self.sanitize = sanitize
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        textField.borderStyle = .none
        textField.backgroundColor = .clear
        textField.clearButtonMode = .never
        textField.adjustsFontForContentSizeCategory = true
        textField.addTarget(
            context.coordinator,
            action: #selector(Coordinator.editingChanged(_:)),
            for: .editingChanged
        )
        return textField
    }

    func updateUIView(_ textField: UITextField, context: Context) {
        context.coordinator.parent = self

        let sanitizedText = sanitize(text)
        if text != sanitizedText {
            DispatchQueue.main.async {
                self.text = sanitizedText
            }
        }

        if textField.text != sanitizedText {
            textField.text = sanitizedText
        }

        textField.placeholder = placeholder
        textField.keyboardType = keyboardType
        textField.textContentType = textContentType
        textField.autocapitalizationType = autocapitalization
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.isSecureTextEntry = isSecure
        textField.font = UIFont.preferredFont(forTextStyle: .body)
        textField.textColor = textColor

        if focusedField == field, !textField.isFirstResponder {
            textField.becomeFirstResponder()
        } else if focusedField != field, textField.isFirstResponder {
            textField.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PayabliPaymentMethodUIKitTextField

        init(_ parent: PayabliPaymentMethodUIKitTextField) {
            self.parent = parent
        }

        @objc func editingChanged(_ textField: UITextField) {
            apply(textField.text ?? "", to: textField)
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.focusedField = parent.field
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.focusedField == parent.field {
                parent.focusedField = nil
            }
            apply(textField.text ?? "", to: textField)
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let currentText = textField.text ?? ""
            guard let textRange = Range(range, in: currentText) else {
                return false
            }

            let proposedText = currentText.replacingCharacters(in: textRange, with: string)
            let sanitizedText = parent.sanitize(proposedText)

            guard sanitizedText == proposedText else {
                apply(sanitizedText, to: textField)
                return false
            }

            return true
        }

        private func apply(_ value: String, to textField: UITextField) {
            let sanitizedText = parent.sanitize(value)
            if textField.text != sanitizedText {
                textField.text = sanitizedText
            }
            if parent.text != sanitizedText {
                parent.text = sanitizedText
            }
        }
    }
}

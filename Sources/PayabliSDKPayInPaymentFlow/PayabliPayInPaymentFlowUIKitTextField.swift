import SwiftUI
import UIKit

extension PayabliPayInPaymentFlowField {
    /// The keyboard this field raises. Held here rather than at each call site so
    /// the form cannot put a field on a keyboard whose dismissal is untested.
    ///
    /// `cardExpiration` opens a wheel and `amount` and `serviceFee` are read back
    /// rather than typed, so none of them raises one at all.
    var keyboardType: UIKeyboardType {
        switch self {
        case .cardNumber, .cardCvv, .achRouting, .achAccount:
            .numberPad
        case .cardZip, .billingZip:
            .numbersAndPunctuation
        case .billingEmail:
            .emailAddress
        default:
            .default
        }
    }
}

struct PayabliPayInPaymentFlowUIKitTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var field: PayabliPayInPaymentFlowField
    @Binding var focusedField: PayabliPayInPaymentFlowField?
    var keyboardType: UIKeyboardType
    var textContentType: UITextContentType?
    var autocapitalization: UITextAutocapitalizationType
    var isSecure: Bool
    var font: UIFont
    var textColor: UIColor
    var placeholderColor: UIColor
    var accessibilityLabel: String
    var accessibilityHint: String?
    var protectsTextContent: Bool
    var sanitize: (String) -> String

    init(
        text: Binding<String>,
        placeholder: String,
        field: PayabliPayInPaymentFlowField,
        focusedField: Binding<PayabliPayInPaymentFlowField?>,
        keyboardType: UIKeyboardType = .default,
        textContentType: UITextContentType? = nil,
        autocapitalization: UITextAutocapitalizationType = .none,
        isSecure: Bool = false,
        font: UIFont = UIFont.preferredFont(forTextStyle: .body),
        textColor: UIColor = .label,
        placeholderColor: UIColor = .placeholderText,
        accessibilityLabel: String,
        accessibilityHint: String? = nil,
        protectsTextContent: Bool = false,
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
        self.font = font
        self.textColor = textColor
        self.placeholderColor = placeholderColor
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityHint = accessibilityHint
        self.protectsTextContent = protectsTextContent
        self.sanitize = sanitize
    }

    /// Keyboards that carry no return key. A field using one cannot end its own
    /// editing, so nothing on screen takes the keyboard back and it covers
    /// whatever sits below the field, including the button that submits the form.
    /// Every other keyboard here already has a way out.
    static func requiresDoneAccessory(_ keyboardType: UIKeyboardType) -> Bool {
        switch keyboardType {
        case .numberPad, .decimalPad, .phonePad, .asciiCapableNumberPad:
            true
        default:
            false
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> UITextField {
        let textField = UITextField(frame: .zero)
        textField.delegate = context.coordinator
        context.coordinator.textField = textField
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

        let visibleText = displayText(for: sanitizedText)
        if textField.text != visibleText {
            textField.text = visibleText
        }

        textField.attributedPlaceholder = attributedPlaceholder
        textField.keyboardType = keyboardType
        textField.textContentType = textContentType
        textField.autocapitalizationType = autocapitalization
        textField.autocorrectionType = .no
        textField.spellCheckingType = .no
        textField.isSecureTextEntry = isSecure
        textField.font = font
        textField.textColor = textColor
        textField.accessibilityLabel = accessibilityLabel
        textField.accessibilityValue = PayabliPayInPaymentFlowAccessibility.textFieldValue(
            text: sanitizedText,
            isSecure: isSecure || protectsTextContent
        )
        textField.accessibilityHint = accessibilityHint
        textField.accessibilityIdentifier = PayabliPayInPaymentFlowAccessibility.fieldIdentifier(field)

        Self.applyAccessory(to: textField, keyboardType: keyboardType, from: context.coordinator)
    }

    /// Separate from `updateUIView` because a `Context` cannot be built outside
    /// SwiftUI, and an accessory's contents never enter the accessibility tree, so
    /// this is the only place the assignment can be checked.
    static func applyAccessory(
        to textField: UITextField,
        keyboardType: UIKeyboardType,
        from coordinator: Coordinator
    ) {
        // Compared by identity so a field that is already carrying the bar keeps
        // the same one: reassigning it while the field is first responder makes
        // UIKit rebuild the input views underneath the person typing.
        let accessory: UIView? = requiresDoneAccessory(keyboardType)
            ? coordinator.doneAccessoryView()
            : nil
        if textField.inputAccessoryView !== accessory {
            textField.inputAccessoryView = accessory
        }
    }

    private var attributedPlaceholder: NSAttributedString? {
        guard !placeholder.isEmpty else { return nil }

        return NSAttributedString(
            string: placeholder,
            attributes: [
                .foregroundColor: placeholderColor,
                .font: font
            ]
        )
    }

    private func displayText(for sanitizedText: String) -> String {
        guard protectsTextContent else { return sanitizedText }
        guard field == .cardNumber else {
            return sanitizedText.map { character in
                character.wholeNumberValue == nil ? character : "•"
            }
            .map(String.init)
            .joined()
        }

        var remainingDigits = sanitizedText.filter { $0.wholeNumberValue != nil }.count
        return sanitizedText.map { character in
            guard character.wholeNumberValue != nil else { return String(character) }
            defer { remainingDigits -= 1 }
            return remainingDigits <= 4 ? String(character) : "•"
        }
        .joined()
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PayabliPayInPaymentFlowUIKitTextField
        weak var textField: UITextField?
        private var doneAccessory: UIInputView?

        init(_ parent: PayabliPayInPaymentFlowUIKitTextField) {
            self.parent = parent
        }

        /// Built once and reused. A `UIToolbar` cannot be used here: as an input
        /// accessory it draws no background and lays its items out floating, so
        /// the control appears alone over the form rather than on a bar. This is a
        /// keyboard-styled input view instead, which spans the keyboard's width
        /// and follows its material in both appearances.
        func doneAccessoryView() -> UIInputView {
            if let doneAccessory {
                return doneAccessory
            }
            let bar = UIInputView(
                frame: CGRect(x: 0, y: 0, width: 0, height: Self.accessoryHeight),
                inputViewStyle: .keyboard
            )
            // UIKit stretches the width to the keyboard's and keeps the height.
            bar.autoresizingMask = .flexibleWidth

            // The keyboard style paints nothing of its own, so the bar carries the
            // same chrome material the keyboard is drawn on. That follows both
            // appearances without a fixed colour in between.
            let material = UIVisualEffectView(effect: UIBlurEffect(style: .systemChromeMaterial))
            material.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(material)
            NSLayoutConstraint.activate([
                material.leadingAnchor.constraint(equalTo: bar.leadingAnchor),
                material.trailingAnchor.constraint(equalTo: bar.trailingAnchor),
                material.topAnchor.constraint(equalTo: bar.topAnchor),
                material.bottomAnchor.constraint(equalTo: bar.bottomAnchor)
            ])

            let done = UIButton(type: .system)
            done.setImage(UIImage(systemName: "checkmark"), for: .normal)
            done.accessibilityLabel = PayabliPayInPaymentFlowAccessibility.keyboardDoneLabel
            done.accessibilityIdentifier = PayabliPayInPaymentFlowAccessibility.keyboardDoneIdentifier
            done.addTarget(self, action: #selector(endEditing), for: .touchUpInside)
            done.translatesAutoresizingMaskIntoConstraints = false
            bar.addSubview(done)

            let target = PayabliPayInPaymentFlowAccessibility.minimumTouchTarget
            NSLayoutConstraint.activate([
                done.trailingAnchor.constraint(equalTo: bar.layoutMarginsGuide.trailingAnchor),
                done.centerYAnchor.constraint(equalTo: bar.centerYAnchor),
                done.widthAnchor.constraint(greaterThanOrEqualToConstant: target),
                done.heightAnchor.constraint(greaterThanOrEqualToConstant: target)
            ])

            doneAccessory = bar
            return bar
        }

        /// Tall enough for the button's own minimum target and the margin around it.
        static let accessoryHeight: CGFloat = 48

        /// Resigns the field that owns this bar rather than asking the application
        /// to end editing everywhere, so the SDK reaches only its own responder.
        @objc func endEditing() {
            textField?.resignFirstResponder()
        }

        @objc func editingChanged(_ textField: UITextField) {
            guard !parent.protectsTextContent else {
                displayCurrentValue(in: textField)
                return
            }
            apply(textField.text ?? "", to: textField)
        }

        func textFieldDidBeginEditing(_ textField: UITextField) {
            parent.focusedField = parent.field
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            if parent.focusedField == parent.field {
                parent.focusedField = nil
            }
            guard !parent.protectsTextContent else {
                displayCurrentValue(in: textField)
                return
            }
            apply(textField.text ?? "", to: textField)
        }

        /// A return key does nothing on its own: `UITextField` keeps first
        /// responder unless a delegate gives it up. Without this, the keyboards
        /// that carry no accessory would have no way back either.
        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            return false
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            guard !parent.protectsTextContent else {
                applyProtectedChange(in: range, replacementString: string, to: textField)
                return false
            }

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

        private func applyProtectedChange(
            in range: NSRange,
            replacementString string: String,
            to textField: UITextField
        ) {
            let currentText = parent.sanitize(parent.text)
            let displayText = parent.displayText(for: currentText)
            guard let displayRange = Range(range, in: displayText) else {
                displayCurrentValue(in: textField)
                return
            }

            let lowerOffset = displayText.distance(from: displayText.startIndex, to: displayRange.lowerBound)
            let upperOffset = displayText.distance(from: displayText.startIndex, to: displayRange.upperBound)
            guard let lowerBound = currentText.index(
                currentText.startIndex,
                offsetBy: lowerOffset,
                limitedBy: currentText.endIndex
            ),
                let upperBound = currentText.index(
                    currentText.startIndex,
                    offsetBy: upperOffset,
                    limitedBy: currentText.endIndex
                )
            else {
                displayCurrentValue(in: textField)
                return
            }

            let proposedText = currentText.replacingCharacters(
                in: lowerBound ..< upperBound,
                with: string
            )
            let sanitizedText = parent.sanitize(proposedText)
            if parent.text != sanitizedText {
                parent.text = sanitizedText
            }
            textField.text = parent.displayText(for: sanitizedText)
        }

        private func displayCurrentValue(in textField: UITextField) {
            let sanitizedText = parent.sanitize(parent.text)
            if parent.text != sanitizedText {
                parent.text = sanitizedText
            }
            textField.text = parent.displayText(for: sanitizedText)
        }
    }
}

import SwiftUI

#if os(iOS)
import UIKit

/// PAN input field with native UIKit cursor handling, brand-aware grouping,
/// smart backspace, and OS-level credit-card autofill.
///
/// The PAN row is the one form field where naive SwiftUI `TextField` UX falls
/// short:
///
/// 1. **Cursor preservation.** SwiftUI re-binds the text on every keystroke,
///    so any reformat ("4242" → "4242 ") moves the caret to the end. Editing
///    in the middle of the PAN is broken.
/// 2. **Smart backspace.** Pressing delete with the caret right after a
///    separator space should remove the digit *before* the space, not the
///    space itself (which would just be re-inserted by the formatter).
/// 3. **Autofill.** `textContentType = .creditCardNumber` lights up the
///    iCloud-Keychain QuickType bar and the strong-box autofill flow — a one-
///    tap PAN entry. SwiftUI's `.textContentType` modifier doesn't reach into
///    the underlying `UITextField` reliably enough on every iOS minor.
///
/// Wrapping `UITextField` directly lets the formatter compute, in one pass:
/// the new formatted text, the new caret offset (in *digit* terms, then mapped
/// back to formatted coordinates), and pre-applies smart-backspace before
/// reformatting. The macOS test build falls back to a plain `TextField` since
/// the form is iOS-first; the macOS path only exists to keep `swift test`
/// green on the CI runner.
@available(iOS 15.0, *)
struct PayabliCardNumberField: UIViewRepresentable {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let onSubmit: () -> Void

    func makeUIView(context: Context) -> UITextField {
        let tf = UITextField()
        tf.delegate = context.coordinator
        tf.keyboardType = .numberPad
        tf.textContentType = .creditCardNumber
        tf.autocorrectionType = .no
        tf.spellCheckingType = .no
        tf.borderStyle = .none
        tf.font = .monospacedDigitSystemFont(
            ofSize: UIFont.preferredFont(forTextStyle: .body).pointSize,
            weight: .regular
        )
        tf.adjustsFontForContentSizeCategory = true
        tf.placeholder = placeholder
        tf.isAccessibilityElement = true
        tf.accessibilityLabel = accessibilityLabel
        tf.accessibilityIdentifier = accessibilityIdentifier
        tf.setContentHuggingPriority(.defaultLow, for: .horizontal)
        return tf
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        // Coordinator carries the up-to-date binding; refreshing it on every
        // updateUIView avoids stale captures across SwiftUI re-renders.
        context.coordinator.parent = self

        if uiView.text != text {
            // External change (autofill, programmatic). Replace and let the
            // selectedTextRange default to the end — UIKit's standard behavior.
            uiView.text = text
        }

        // We only *claim* focus programmatically (for e.g. starting-at-PAN).
        // We DO NOT call `resignFirstResponder` here: during a re-render
        // triggered by typing, the `isFocused` binding can momentarily report
        // a stale value while SwiftUI reconciles `@FocusState`, and resigning
        // in that window dismisses the keyboard after every keystroke. The
        // natural UIKit hand-off (whichever field becomes first responder
        // pushes the previous one out) makes the resign-on-render branch
        // unnecessary.
        if isFocused, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: PayabliCardNumberField

        init(parent: PayabliCardNumberField) {
            self.parent = parent
        }

        // MARK: - Editing pipeline

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            let oldText = (textField.text ?? "") as NSString

            // Smart backspace: a single-char deletion of a separator space
            // becomes a 2-char deletion (space + the digit before it). The
            // formatter would otherwise just re-insert the space, leaving the
            // user staring at an unchanged field.
            var workingRange = range
            if string.isEmpty,
               range.length == 1,
               range.location > 0,
               oldText.substring(with: range) == " " {
                workingRange = NSRange(location: range.location - 1, length: 2)
            }

            let proposed = oldText.replacingCharacters(in: workingRange, with: string)
            let allDigits = proposed.filter(\.isNumber)
            let brand = PaymentValidators.cardBrand(for: allDigits)
            let cap = PaymentValidators.maxDigits(for: brand)
            let cappedDigits = String(allDigits.prefix(cap))
            let formatted = PaymentValidators.formatCardNumber(cappedDigits, brand: brand)

            // Caret math: digits-before-the-edit + digits-inserted, clamped
            // to the post-cap digit count. Then walk `formatted` to find the
            // index of the n-th digit boundary.
            let prefixDigits = oldText.substring(to: workingRange.location).filter(\.isNumber).count
            let insertedDigits = string.filter(\.isNumber).count
            let targetDigitIndex = min(prefixDigits + insertedDigits, cappedDigits.count)

            var cursorOffset = 0
            var digitsSeen = 0
            for ch in formatted {
                if digitsSeen >= targetDigitIndex { break }
                if ch.isNumber { digitsSeen += 1 }
                cursorOffset += 1
            }
            // Hit the end before reaching the target — clamp to end-of-string.
            if digitsSeen < targetDigitIndex {
                cursorOffset = formatted.count
            }

            textField.text = formatted
            if let pos = textField.position(
                from: textField.beginningOfDocument,
                offset: cursorOffset
            ) {
                textField.selectedTextRange = textField.textRange(from: pos, to: pos)
            }

            // Sync the SwiftUI binding (drives cardBrand derivation, validation,
            // and the auto-advance .onChange in CardFormView).
            if parent.text != formatted {
                parent.text = formatted
            }

            return false  // We applied the change manually.
        }

        // MARK: - Focus events
        //
        // Writes to the `isFocused` binding (which is backed by the parent's
        // `@FocusState`) are deferred to the next runloop tick. Writing the
        // FocusState synchronously from a UIKit delegate callback causes
        // SwiftUI to reconcile focus mid-event; because no SwiftUI view has
        // `.focused(..., equals: .cardNumber)` attached (the PAN is UIKit-
        // backed), SwiftUI has no target to focus and ends up resigning the
        // UITextField that just started editing — dismissing the keyboard on
        // every keystroke. Deferring lets UIKit's own first-responder
        // transition settle before SwiftUI touches focus state.

        func textFieldDidBeginEditing(_ textField: UITextField) {
            DispatchQueue.main.async { [weak self] in
                guard let self, !self.parent.isFocused else { return }
                self.parent.isFocused = true
            }
        }

        func textFieldDidEndEditing(_ textField: UITextField) {
            DispatchQueue.main.async { [weak self] in
                guard let self, self.parent.isFocused else { return }
                self.parent.isFocused = false
            }
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            parent.onSubmit()
            return false
        }
    }
}

#else

// MARK: - macOS fallback (test builds only)
//
// The form is iOS-first; this fallback exists so `swift test` on the macOS
// runner can compile the package. It does not aim for parity — no smart
// backspace, no cursor preservation, no autofill.
@available(macOS 12.0, *)
struct PayabliCardNumberField: View {
    @Binding var text: String
    @Binding var isFocused: Bool
    let placeholder: String
    let accessibilityLabel: String
    let accessibilityIdentifier: String
    let onSubmit: () -> Void

    var body: some View {
        TextField(placeholder, text: $text)
            .onSubmit(onSubmit)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityIdentifier(accessibilityIdentifier)
    }
}

#endif

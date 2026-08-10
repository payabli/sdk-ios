#if DEBUG
import PayabliSDKPayInPaymentFlow
import SwiftUI
import UIKit

/// Debug-only QA convenience that pre-populates the PayInPaymentFlow form with
/// test data read from `DebugPrefill.json` at runtime.
///
/// The SDK renders the form and owns its field state, so there is no public API
/// to seed values directly. Instead we locate each on-screen text field by the
/// stable `accessibilityIdentifier` the SDK assigns
/// (`payabli.payInPaymentFlow.field.<field.rawValue>`), set its text, and fire
/// `.editingChanged` so the value flows through the SDK's own input path into
/// its view model — exactly as if a person had typed it.
///
/// Values live in a JSON resource (never hard-coded here), and this entire file
/// is compiled only in Debug builds, so nothing ships in Release.
///
/// Limitation: the expiration field is a SwiftUI wheel-picker, not a text field,
/// so it cannot be prefilled this way — pick `07/30` (or the value from the JSON)
/// manually.
enum DebugPrefill {
    /// Runtime-read prefill values. Only the fields that map to editable text
    /// inputs are applied; `cardExpiration` is decoded for documentation but is
    /// entered manually (picker field).
    struct Values: Decodable {
        var cardholderName: String?
        var cardNumber: String?
        var cardCvv: String?
        var cardZip: String?
        var cardExpiration: String?
        var firstName: String?
        var lastName: String?
        var billingEmail: String?
        var customerNumber: String?
        var achHolder: String?
        var achRouting: String?
        var achAccount: String?
    }

    /// Decoded once from `DebugPrefill.json` in the app bundle.
    static let values: Values? = {
        guard let url = Bundle.main.url(forResource: "DebugPrefill", withExtension: "json") else {
            print("[DebugPrefill] DebugPrefill.json not found in bundle")
            return nil
        }
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode(Values.self, from: data)
        } catch {
            print("[DebugPrefill] Failed to decode DebugPrefill.json: \(error)")
            return nil
        }
    }()

    /// Fills every visible text field whose identifier matches a value in the
    /// JSON. Safe to call repeatedly; missing fields are skipped.
    @MainActor
    static func fill() {
        guard let values else { return }

        let mapping: [(PayabliPayInPaymentFlowField, String?)] = [
            (.cardholderName, values.cardholderName),
            (.cardNumber, values.cardNumber),
            (.cardCvv, values.cardCvv),
            (.cardZip, values.cardZip),
            (.firstName, values.firstName),
            (.lastName, values.lastName),
            (.billingEmail, values.billingEmail),
            (.customerNumber, values.customerNumber),
            (.achHolder, values.achHolder),
            (.achRouting, values.achRouting),
            (.achAccount, values.achAccount)
        ]

        let textFields = onScreenTextFields()
        for (field, value) in mapping {
            guard let value, !value.isEmpty else { continue }
            let identifier = "payabli.payInPaymentFlow.field.\(field.rawValue)"
            guard let textField = textFields.first(where: { $0.accessibilityIdentifier == identifier }) else {
                continue
            }
            inject(value, into: textField)
        }
    }

    /// Feeds `value` into `textField` through the SDK's own input path.
    ///
    /// A protected field ignores direct `.text` assignment, so the value goes in
    /// through the delegate, as a paste over the whole field.
    ///
    /// The delegate's answer has to be honoured: a protected field applies the
    /// change itself and says `false`, an unprotected one says `true` and leaves
    /// the applying to the caller.
    private static func inject(_ value: String, into textField: UITextField) {
        let current = (textField.text ?? "") as NSString
        let fullRange = NSRange(location: 0, length: current.length)
        let shouldApply = textField.delegate?.textField?(
            textField,
            shouldChangeCharactersIn: fullRange,
            replacementString: value
        ) ?? true

        guard shouldApply else { return }
        textField.text = current.replacingCharacters(in: fullRange, with: value)
        textField.sendActions(for: .editingChanged)
    }

    /// Text fields of the frontmost presentation only.
    ///
    /// A presented sheet does not unmount the form behind it, and both carry the
    /// same accessibility identifiers, so searching every window and taking the
    /// first match could prefill the covered form instead of the sheet. Which one
    /// won depended on view order, which made the sheet prefill nondeterministic.
    private static func onScreenTextFields() -> [UITextField] {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)

        let root = windows.first(where: \.isKeyWindow) ?? windows.last
        var result: [UITextField] = []
        if let host = topmostViewController(from: root?.rootViewController) {
            collectTextFields(in: host.view, into: &result)
        }
        // A form outside any view controller still has to be reachable.
        if result.isEmpty, let root {
            collectTextFields(in: root, into: &result)
        }
        return result
    }

    private static func topmostViewController(
        from controller: UIViewController?
    ) -> UIViewController? {
        guard let controller else { return nil }
        if let presented = controller.presentedViewController {
            return topmostViewController(from: presented)
        }
        return controller
    }

    private static func collectTextFields(in view: UIView, into result: inout [UITextField]) {
        if let textField = view as? UITextField {
            result.append(textField)
        }
        for subview in view.subviews {
            collectTextFields(in: subview, into: &result)
        }
    }
}

/// Debug-only button that triggers ``DebugPrefill/fill()``.
struct DebugPrefillButton: View {
    var body: some View {
        Button {
            DebugPrefill.fill()
        } label: {
            Label("Prefill test data (Debug)", systemImage: "wand.and.stars")
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.bordered)
        .tint(.payabliWarning)
    }
}
#endif

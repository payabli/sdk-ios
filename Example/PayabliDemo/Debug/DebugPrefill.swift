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
    /// The SDK marks these fields `protectsTextContent`, so its `editingChanged`
    /// handler ignores direct `.text` assignments — user input only lands via the
    /// `textField(_:shouldChangeCharactersIn:replacementString:)` delegate call.
    /// We invoke that delegate method with a range spanning the whole field, which
    /// is exactly what UIKit does when a value is pasted over a selection, so the
    /// SDK's formatting/validation and view model update just as if typed.
    private static func inject(_ value: String, into textField: UITextField) {
        let current = (textField.text ?? "") as NSString
        let fullRange = NSRange(location: 0, length: current.length)
        _ = textField.delegate?.textField?(
            textField,
            shouldChangeCharactersIn: fullRange,
            replacementString: value
        )
    }

    private static func onScreenTextFields() -> [UITextField] {
        let windows = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)

        var result: [UITextField] = []
        for window in windows {
            collectTextFields(in: window, into: &result)
        }
        return result
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

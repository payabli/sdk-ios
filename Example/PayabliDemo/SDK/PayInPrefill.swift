import PayabliSDKPayInPaymentFlow

/// The form fields this app can fill, and how to find one on screen.
///
/// The SDK owns the form's field state and offers no way to seed it, so the debug
/// prefill reaches the rendered fields by the `accessibilityIdentifier` the SDK
/// assigns. That identifier is built from an SDK type, so it is named here rather
/// than rebuilt by the screen that types into it.
///
/// The sibling seeds through the form's own `initialValues` instead, so nothing
/// there reaches around the form. This platform has no such parameter.
enum PayInPrefillField: CaseIterable {
    case cardholderName
    case cardNumber
    case cardCvv
    case cardZip
    case firstName
    case lastName
    case billingEmail
    case customerNumber
    case achHolder
    case achRouting
    case achAccount

    /// What the SDK sets on the rendered text field.
    var accessibilityIdentifier: String {
        "payabli.payInPaymentFlow.field.\(field.rawValue)"
    }

    private var field: PayabliPayInPaymentFlowField {
        switch self {
        case .cardholderName: return .cardholderName
        case .cardNumber: return .cardNumber
        case .cardCvv: return .cardCvv
        case .cardZip: return .cardZip
        case .firstName: return .firstName
        case .lastName: return .lastName
        case .billingEmail: return .billingEmail
        case .customerNumber: return .customerNumber
        case .achHolder: return .achHolder
        case .achRouting: return .achRouting
        case .achAccount: return .achAccount
        }
    }
}

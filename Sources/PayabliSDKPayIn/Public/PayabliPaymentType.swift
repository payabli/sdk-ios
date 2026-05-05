import Foundation

/// The payment method type presented by the PayIn component.
///
/// See PRD §5.3 FR-6.4.
@objc public enum PayabliPaymentType: Int, Sendable {
    case card = 0
    case ach = 1
    case applePay = 2
    case tapToPay = 3
}

import Foundation

public struct PayabliPayInPaymentFlowValidation: Sendable {
    public var requiresLuhnCheck: Bool
    public var validatesACHRoutingChecksum: Bool

    public init(
        requiresLuhnCheck: Bool = true,
        validatesACHRoutingChecksum: Bool = true
    ) {
        self.requiresLuhnCheck = requiresLuhnCheck
        self.validatesACHRoutingChecksum = validatesACHRoutingChecksum
    }

    public static let `default` = PayabliPayInPaymentFlowValidation()
}

extension PayabliPayInPaymentFlowValidation {
    var payabliViewModelSignature: String {
        "luhn:\(requiresLuhnCheck),achRouting:\(validatesACHRoutingChecksum)"
    }
}

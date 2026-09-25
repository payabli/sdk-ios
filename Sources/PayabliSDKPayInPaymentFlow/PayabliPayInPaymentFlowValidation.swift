import Foundation

public struct PayabliPayInPaymentFlowValidation: Sendable {
    public var requiresLuhnCheck: Bool
    public var validatesRoutingNumberChecksum: Bool

    public init(
        requiresLuhnCheck: Bool = true,
        validatesRoutingNumberChecksum: Bool = true
    ) {
        self.requiresLuhnCheck = requiresLuhnCheck
        self.validatesRoutingNumberChecksum = validatesRoutingNumberChecksum
    }

    public static let `default` = PayabliPayInPaymentFlowValidation()
}

extension PayabliPayInPaymentFlowValidation {
    var payabliViewModelSignature: String {
        "luhn:\(requiresLuhnCheck),routingNumber:\(validatesRoutingNumberChecksum)"
    }
}

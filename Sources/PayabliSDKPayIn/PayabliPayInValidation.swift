import Foundation

public struct PayabliPayInValidation: Sendable {
    public var requiresLuhnCheck: Bool
    public var validatesRoutingNumberChecksum: Bool

    public init(
        requiresLuhnCheck: Bool = true,
        validatesRoutingNumberChecksum: Bool = true
    ) {
        self.requiresLuhnCheck = requiresLuhnCheck
        self.validatesRoutingNumberChecksum = validatesRoutingNumberChecksum
    }

    public static let `default` = PayabliPayInValidation()
}

extension PayabliPayInValidation {
    var payabliViewModelSignature: String {
        "luhn:\(requiresLuhnCheck),routingNumber:\(validatesRoutingNumberChecksum)"
    }
}

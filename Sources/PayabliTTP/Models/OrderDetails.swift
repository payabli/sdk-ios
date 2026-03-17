import Foundation

public struct OrderDetails: Sendable {
    public let orderId: String
    public let description: String?

    public init(orderId: String, description: String? = nil) {
        self.orderId = orderId
        self.description = description
    }
}

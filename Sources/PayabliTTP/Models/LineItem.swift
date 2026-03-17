import Foundation

public struct LineItem: Sendable {
    public let name: String
    public let amount: Decimal
    public let quantity: Int
    public let description: String?

    public init(name: String, amount: Decimal, quantity: Int = 1, description: String? = nil) {
        self.name = name
        self.amount = amount
        self.quantity = quantity
        self.description = description
    }
}

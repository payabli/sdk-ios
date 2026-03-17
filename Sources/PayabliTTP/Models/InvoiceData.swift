import Foundation

public struct InvoiceData: Sendable {
    public let invoiceNumber: String
    public let items: [LineItem]

    public init(invoiceNumber: String, items: [LineItem] = []) {
        self.invoiceNumber = invoiceNumber
        self.items = items
    }
}

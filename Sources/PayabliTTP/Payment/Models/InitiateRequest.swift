import Foundation

/// Body for POST /api/v2/MoneyIn/initiate
/// Matches the exact structure the POC currently sends.
struct InitiateRequest: Encodable {
    let entry: String
    let orderId: String?
    let orderDescription: String?
    let paymentDetails: PaymentDetails
    let paymentMethod: PaymentMethod
    let customerData: CustomerPayload?
    let invoiceData: InvoicePayload?

    struct PaymentDetails: Encodable {
        let totalAmount: Decimal
        let serviceFee: Decimal?
    }

    struct PaymentMethod: Encodable {
        let method: String
        let device: String
    }

    struct CustomerPayload: Encodable {
        let firstName: String?
        let lastName: String?
    }

    struct InvoicePayload: Encodable {
        let invoiceNumber: String
        let items: [InvoiceItem]?

        struct InvoiceItem: Encodable {
            let name: String
            let amount: Decimal
            let quantity: Int
        }
    }
}

import Foundation

/// Response from POST /api/v2/MoneyIn/initiate
/// Matches the POC structure: { data: { paymentTransId: "..." } }
struct TransactionResponse: Decodable {
    let data: TransactionData?

    var paymentTransId: String? {
        data?.paymentTransId
    }
}

struct TransactionData: Decodable {
    let paymentTransId: String?
}

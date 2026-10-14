import Foundation

/// A transaction as the details route answers it, keyed in PascalCase.
///
/// Only the fields every platform's transaction carries are declared, so nothing else in the record,
/// card or personal data included, is decoded.
struct TransactionDetailsRecord: Decodable {
    let paymentTransId: String?
    let gatewayTransId: String?
    let orderId: String?
    let method: String?
    let transStatus: Int?
    let paypointId: Int64?
    let totalAmount: Double?
    let netAmount: Double?
    let feeAmount: Double?
    let surchargeFee: Double?

    enum CodingKeys: String, CodingKey {
        case paymentTransId = "PaymentTransId"
        case gatewayTransId = "GatewayTransId"
        case orderId = "OrderId"
        case method = "Method"
        case transStatus = "TransStatus"
        case paypointId = "PaypointId"
        case totalAmount = "TotalAmount"
        case netAmount = "NetAmount"
        case feeAmount = "FeeAmount"
        case surchargeFee = "SurchargeFee"
    }

    var transaction: PayabliPayInTransaction {
        PayabliPayInTransaction(
            paymentTransId: paymentTransId,
            gatewayTransId: gatewayTransId,
            orderId: orderId,
            method: method,
            transStatus: transStatus,
            paypointId: paypointId,
            totalAmount: totalAmount,
            netAmount: netAmount,
            feeAmount: feeAmount,
            surchargeFee: surchargeFee
        )
    }
}

/// The older envelope's numeric code, the one field a details refusal is classified by.
struct LegacyRefusal: Decodable {
    let responseCode: Int?
}

import Foundation

/// A transaction as the details route answers it, keyed in PascalCase or camelCase.
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

    init(from decoder: any Decoder) throws {
        let record = try decoder.container(keyedBy: EitherCaseKey.self)
        paymentTransId = try record.value(String.self, "paymentTransId")
        gatewayTransId = try record.value(String.self, "gatewayTransId")
        orderId = try record.value(String.self, "orderId")
        method = try record.value(String.self, "method")
        transStatus = try record.value(Int.self, "transStatus")
        paypointId = try record.value(Int64.self, "paypointId")
        totalAmount = try record.amount("totalAmount")
        netAmount = try record.amount("netAmount")
        feeAmount = try record.amount("feeAmount")
        surchargeFee = try record.amount("surchargeFee")
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

    init(from decoder: any Decoder) throws {
        responseCode = try decoder.container(keyedBy: EitherCaseKey.self).value(Int.self, "responseCode")
    }
}

/// A key matched in its camelCase spelling or with its first letter capitalised.
private struct EitherCaseKey: CodingKey {
    let stringValue: String
    var intValue: Int? {
        nil
    }

    init(stringValue: String) {
        self.stringValue = stringValue
    }

    init?(intValue _: Int) {
        nil
    }
}

private extension KeyedDecodingContainer where Key == EitherCaseKey {
    /// The value under the PascalCase spelling of `name`, else under `name` itself.
    ///
    /// - Parameter type: the type the value decodes as.
    /// - Parameter name: the key as the record writes it, in camelCase.
    /// - Returns: the decoded value, or nil when the record carries none.
    func value<T: Decodable>(_ type: T.Type, _ name: String) throws -> T? {
        try decodeIfPresent(type, forKey: key(for: name))
    }

    /// An amount written as a JSON number or as a decimal string. Any other string is refused.
    ///
    /// - Parameter name: the key the amount sits under, in camelCase.
    /// - Returns: the amount, or nil when the record carries none.
    func amount(_ name: String) throws -> Double? {
        let key = key(for: name)
        if let number = try? decodeIfPresent(Double.self, forKey: key) {
            return number
        }
        guard let text = try decodeIfPresent(String.self, forKey: key) else { return nil }
        guard text.range(of: Self.decimal, options: .regularExpression) != nil, let number = Double(text), number.isFinite else {
            throw DecodingError.dataCorruptedError(forKey: key, in: self, debugDescription: "Not an amount")
        }
        return number
    }

    /// Plain decimal notation, so a hexadecimal, infinite or padded value is not taken for an amount.
    private static var decimal: String {
        #"^[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?$"#
    }

    private func key(for name: String) -> EitherCaseKey {
        let pascal = EitherCaseKey(stringValue: name.prefix(1).uppercased() + name.dropFirst())
        return contains(pascal) ? pascal : EitherCaseKey(stringValue: name)
    }
}

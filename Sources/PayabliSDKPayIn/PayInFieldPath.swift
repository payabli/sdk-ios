/// Where a refused value sits in the request, as ``PayabliPayInError/InvalidInput/field`` names it. A payment method's
/// members are the encoder's own keys under `paymentMethod.`.
enum PayInFieldPath {
    static let entryPoint = "entryPoint"
    static let transId = "transId"
    static let paymentReference = "paymentReference"
    static let idempotencyKey = "idempotencyKey"
    static let paymentMethod = "paymentMethod"
    static let totalAmount = details("totalAmount")
    static let serviceFee = details("serviceFee")
    static let surchargeFee = details("surchargeFee")

    /// - Parameter key: the payment method member, as the payment encoder writes it.
    /// - Returns: the member's path under `paymentMethod.`.
    static func method(_ key: PayabliPayInPaymentMethod.CodingKeys) -> String {
        "\(paymentMethod).\(key.stringValue)"
    }

    /// - Parameter key: the payment method member, as the stored-method encoder writes it.
    /// - Returns: the member's path under `paymentMethod.`.
    static func storedMethod(_ key: PayabliPayInMethodInput.CodingKeys) -> String {
        "\(paymentMethod).\(key.stringValue)"
    }

    /// - Parameter field: a form field a payer fills in.
    /// - Returns: where its value sits in the request.
    static func form(_ field: PayabliPayInField) -> String {
        switch field {
        case .cardholderName: storedMethod(.cardHolder)
        case .cardNumber: storedMethod(.cardnumber)
        case .cardExpiration: storedMethod(.cardexp)
        case .cardSecurityCode: storedMethod(.cardcvv)
        case .cardPostalCode: storedMethod(.cardzip)
        case .accountHolder: storedMethod(.achHolder)
        case .routingNumber: storedMethod(.achRouting)
        case .accountNumber: storedMethod(.achAccount)
        case .accountType: storedMethod(.achAccountType)
        case .accountHolderType: storedMethod(.achHolderType)
        case .secCode: storedMethod(.achCode)
        case .firstName, .lastName, .customerNumber, .billingEmail: "customerData.\(field.rawValue)"
        case .billingPostalCode: "customerData.billingZip"
        case .amount: totalAmount
        case .serviceFee: serviceFee
        case .surchargeFee: surchargeFee
        }
    }

    /// - Parameter name: the payment details member, as the request writes it.
    /// - Returns: the member's path under `paymentDetails.`.
    static func details(_ name: String) -> String {
        "paymentDetails.\(name)"
    }
}

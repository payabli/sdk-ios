import PayabliSDKCore

/// The form fields a validation refusal names. A key is matched on its last segment and without case,
/// so a field named bare or under its parent object resolves to the same box.
enum PayabliPayInPaymentFlowRejectedFields {
    static func fields(in error: any Error) -> Set<PayabliPayInPaymentFlowField> {
        guard case let .validation(refusal)? = error as? PayabliPaymentError else { return [] }
        return Set((refusal.errors ?? [:]).keys.compactMap(field(named:)))
    }

    static func field(named name: String) -> PayabliPayInPaymentFlowField? {
        let lastSegment = name.split(separator: ".").last.map(String.init) ?? name
        return fieldsByWireName[lastSegment.lowercased()]
    }

    private typealias MethodKey = PayabliPayInPaymentMethod.CodingKeys

    /// Card and bank-account names are the encoder's own keys; the customer names are checked against an
    /// encoded request by a test, because `Codable` synthesises them.
    static let fieldsByWireName: [String: PayabliPayInPaymentFlowField] = {
        let pairs: [(String, PayabliPayInPaymentFlowField)] = [
            (MethodKey.cardHolder.stringValue, .cardholderName),
            (MethodKey.cardnumber.stringValue, .cardNumber),
            (MethodKey.cardexp.stringValue, .cardExpiration),
            (MethodKey.cardcvv.stringValue, .cardCvv),
            (MethodKey.cardzip.stringValue, .cardZip),
            (MethodKey.achHolder.stringValue, .achHolder),
            (MethodKey.achRouting.stringValue, .achRouting),
            (MethodKey.achAccount.stringValue, .achAccount),
            (MethodKey.achAccountType.stringValue, .achAccountType),
            (MethodKey.achHolderType.stringValue, .achHolderType),
            (MethodKey.achCode.stringValue, .achSecCode),
            (MethodKey.device.stringValue, .achDevice),
            ("firstName", .firstName),
            ("lastName", .lastName),
            ("customerNumber", .customerNumber),
            ("billingEmail", .billingEmail),
            ("billingZip", .billingZip)
        ]
        return Dictionary(uniqueKeysWithValues: pairs.map { ($0.0.lowercased(), $0.1) })
    }()
}

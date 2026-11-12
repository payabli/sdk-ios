import PayabliSDKCore

/// The form fields a refusal names: the service's validation errors, or the one field the payment flow refused
/// before sending. A key is matched on its last segment and without case, so a field named bare or under its parent
/// object resolves to the same box.
enum PayabliPayInRejectedFields {
    /// - Parameter error: what the submission ended in.
    /// - Returns: the fields it blamed that the form has a box for, or none.
    static func fields(in error: any Error) -> Set<PayabliPayInField> {
        switch error {
        case let unsettled as PayabliPayInError.Unsettled:
            return unsettled.rejectedFields
        case let refusal as PayabliPayInError.InvalidInput:
            return Set([refusal.field].compactMap { $0.flatMap(field(named:)) })
        case let PayabliPaymentError.validation(refusal):
            return Set(refusal.errors.keys.compactMap(field(named:)))
        default:
            return []
        }
    }

    static func field(named name: String) -> PayabliPayInField? {
        let lastSegment = name.split(separator: ".").last.map(String.init) ?? name
        return fieldsByWireName[lastSegment.lowercased()]
    }

    private typealias MethodKey = PayabliPayInPaymentMethod.CodingKeys

    /// Card and bank-account names are the encoder's own keys; the customer names are checked against an
    /// encoded request by a test, because `Codable` synthesises them. The amount, the fee and the
    /// description carry no mapping: the figures are read back rather than typed, so a mark on either
    /// could not be cleared by editing it, and no refusal names the description.
    static let fieldsByWireName: [String: PayabliPayInField] = {
        let pairs: [(String, PayabliPayInField)] = [
            (MethodKey.cardHolder.stringValue, .cardholderName),
            (MethodKey.cardnumber.stringValue, .cardNumber),
            (MethodKey.cardexp.stringValue, .cardExpiration),
            (MethodKey.cardcvv.stringValue, .cardSecurityCode),
            (MethodKey.cardzip.stringValue, .cardPostalCode),
            (MethodKey.achHolder.stringValue, .accountHolder),
            (MethodKey.achRouting.stringValue, .routingNumber),
            (MethodKey.achAccount.stringValue, .accountNumber),
            (MethodKey.achAccountType.stringValue, .accountType),
            (MethodKey.achHolderType.stringValue, .accountHolderType),
            ("firstName", .firstName),
            ("lastName", .lastName),
            ("customerNumber", .customerNumber),
            ("billingEmail", .billingEmail),
            ("billingZip", .billingPostalCode)
        ]
        return Dictionary(uniqueKeysWithValues: pairs.map { ($0.0.lowercased(), $0.1) })
    }()
}

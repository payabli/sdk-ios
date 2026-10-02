import Foundation
import PayabliSDKCore

enum PayInPaymentFlowJSONBody {
    private struct RawNumber {
        let text: String
    }

    static func encode(_ body: some Encodable) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let encoded = try encoder.encode(body)
        let object = try JSONSerialization.jsonObject(with: encoded)
        return try data(from: normalizingCurrencyFields(in: object))
    }

    static func data(from value: Any) throws -> Data {
        try Data(jsonString(from: value).utf8)
    }

    /// Writes the payment's own amounts at two places. Nothing else is read as money: free-form data such as
    /// `additionalData` is sent exactly as the host gave it, whatever its keys are called.
    static func normalizingCurrencyFields(in value: Any) throws -> Any {
        guard var body = value as? [String: Any], let details = body["paymentDetails"] as? [String: Any] else {
            return value
        }
        body["paymentDetails"] = try details.reduce(into: [String: Any]()) { result, pair in
            guard isCurrencyField(pair.key), let number = pair.value as? NSNumber,
                  CFGetTypeID(number) != CFBooleanGetTypeID()
            else {
                result[pair.key] = pair.value
                return
            }
            guard let sent = PayInAmount.sendable(number.doubleValue) else {
                throw PayabliPayInError.invalidInput("paymentDetails.\(pair.key) is out of range.")
            }
            result[pair.key] = RawNumber(text: formattedCurrencyAmount(sent))
        }
        return body
    }

    private static func jsonString(from value: Any) throws -> String {
        switch value {
        case let rawNumber as RawNumber:
            return rawNumber.text
        case let dictionary as [String: Any]:
            let pairs = try dictionary.keys.sorted().map { key in
                let encodedValue = try jsonString(from: dictionary[key] ?? NSNull())
                return try "\(quoted(key)):\(encodedValue)"
            }
            return "{\(pairs.joined(separator: ","))}"
        case let array as [Any]:
            let values = try array.map(jsonString)
            return "[\(values.joined(separator: ","))]"
        case let string as String:
            return try quoted(string)
        case let number as NSNumber:
            if CFGetTypeID(number) == CFBooleanGetTypeID() {
                return number.boolValue ? "true" : "false"
            }
            return number.stringValue
        case _ as NSNull:
            return "null"
        default:
            throw PayabliGenericError(
                code: .decodingError,
                reason: "Failed to serialize payment capture JSON body"
            )
        }
    }

    private static func quoted(_ value: String) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: [value])
        guard let text = String(data: data, encoding: .utf8) else {
            throw PayabliGenericError(
                code: .decodingError,
                reason: "Failed to serialize payment capture JSON string"
            )
        }
        return String(text.dropFirst().dropLast())
    }

    private static func isCurrencyField(_ key: String) -> Bool {
        key == "totalAmount" || key == "serviceFee" || key == "surchargeFee"
    }

    private static func formattedCurrencyAmount(_ rounded: Decimal) -> String {
        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false

        return formatter.string(from: NSDecimalNumber(decimal: rounded)) ?? "\(rounded)"
    }
}

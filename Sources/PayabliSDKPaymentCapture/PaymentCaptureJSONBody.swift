import Foundation
import PayabliSDKCore

enum PaymentCaptureJSONBody {
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

    static func normalizingCurrencyFields(in value: Any) -> Any {
        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, pair in
                if isCurrencyField(pair.key), let amount = doubleValue(pair.value) {
                    result[pair.key] = RawNumber(text: formattedCurrencyAmount(amount))
                } else {
                    result[pair.key] = normalizingCurrencyFields(in: pair.value)
                }
            }
        }

        if let array = value as? [Any] {
            return array.map(normalizingCurrencyFields)
        }

        return value
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
        key == "totalAmount" || key == "serviceFee"
    }

    private static func doubleValue(_ value: Any) -> Double? {
        if let number = value as? NSNumber {
            return number.doubleValue
        }
        if let string = value as? String {
            return Double(string)
        }
        return nil
    }

    private static func formattedCurrencyAmount(_ value: Double) -> String {
        var decimal = Decimal(value)
        var rounded = Decimal()
        NSDecimalRound(&rounded, &decimal, 2, .plain)

        let formatter = NumberFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        formatter.usesGroupingSeparator = false

        return formatter.string(from: NSDecimalNumber(decimal: rounded)) ?? String(format: "%.2f", value)
    }
}

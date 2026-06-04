import Foundation
import PayabliSDKCore

public typealias PayabliPayInPaymentFlowDiagnosticHandler = @Sendable (PayabliPayInPaymentFlowDiagnosticEntry) -> Void

public struct PayabliPayInPaymentFlowDiagnostics: Sendable {
    public let isEnabled: Bool
    public let handler: PayabliPayInPaymentFlowDiagnosticHandler?

    public init(
        isEnabled: Bool = false,
        handler: PayabliPayInPaymentFlowDiagnosticHandler? = nil
    ) {
        self.isEnabled = isEnabled
        self.handler = handler
    }

    public static let disabled = PayabliPayInPaymentFlowDiagnostics()

    public static func enabled(
        handler: @escaping PayabliPayInPaymentFlowDiagnosticHandler
    ) -> PayabliPayInPaymentFlowDiagnostics {
        PayabliPayInPaymentFlowDiagnostics(isEnabled: true, handler: handler)
    }
}

public struct PayabliPayInPaymentFlowDiagnosticEntry: Identifiable, Sendable {
    public enum Phase: String, Sendable {
        case request
        case response
        case failure
    }

    public let id: UUID
    public let phase: Phase
    public let timestamp: Date
    public let method: String
    public let url: String
    public let statusCode: Int?
    public let headers: [String: String]
    public let body: String?
    public let durationMilliseconds: Double?
    public let errorDescription: String?

    public init(
        id: UUID = UUID(),
        phase: Phase,
        timestamp: Date = Date(),
        method: String,
        url: String,
        statusCode: Int? = nil,
        headers: [String: String] = [:],
        body: String? = nil,
        durationMilliseconds: Double? = nil,
        errorDescription: String? = nil
    ) {
        self.id = id
        self.phase = phase
        self.timestamp = timestamp
        self.method = method
        self.url = url
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.durationMilliseconds = durationMilliseconds
        self.errorDescription = errorDescription
    }
}

extension PayabliPayInPaymentFlowDiagnostics {
    func logRequest(_ request: PayabliRequest, baseURL: URL?) {
        guard isEnabled, let handler else { return }
        handler(PayabliPayInPaymentFlowDiagnosticEntry(
            phase: .request,
            method: request.method.rawValue,
            url: Self.urlString(for: request, baseURL: baseURL),
            headers: Self.redactedHeaders(request.headers),
            body: Self.redactedBodyString(request.body)
        ))
    }

    func logResponse(
        _ response: PayabliResponse,
        request: PayabliRequest,
        baseURL: URL?,
        durationMilliseconds: Double
    ) {
        guard isEnabled, let handler else { return }
        handler(PayabliPayInPaymentFlowDiagnosticEntry(
            phase: .response,
            method: request.method.rawValue,
            url: Self.urlString(for: request, baseURL: baseURL),
            statusCode: response.statusCode,
            headers: Self.redactedHeaders(response.headers),
            body: Self.redactedBodyString(response.body),
            durationMilliseconds: durationMilliseconds
        ))
    }

    func logFailure(
        _ error: Error,
        request: PayabliRequest,
        baseURL: URL?,
        durationMilliseconds: Double
    ) {
        guard isEnabled, let handler else { return }
        handler(PayabliPayInPaymentFlowDiagnosticEntry(
            phase: .failure,
            method: request.method.rawValue,
            url: Self.urlString(for: request, baseURL: baseURL),
            headers: Self.redactedHeaders(request.headers),
            durationMilliseconds: durationMilliseconds,
            errorDescription: Self.diagnosticMessage(for: error)
        ))
    }

    private static func urlString(for request: PayabliRequest, baseURL: URL?) -> String {
        guard let baseURL,
              var components = URLComponents(
                  url: baseURL.appendingPathComponent(request.path),
                  resolvingAgainstBaseURL: false
              )
        else {
            var path = request.path
            if !request.query.isEmpty {
                var components = URLComponents()
                components.queryItems = request.query
                path += components.url?.absoluteString ?? ""
            }
            return path
        }

        if !request.query.isEmpty {
            components.queryItems = request.query
        }
        return components.url?.absoluteString ?? request.path
    }

    private static func redactedHeaders(_ headers: [String: String]) -> [String: String] {
        Dictionary(uniqueKeysWithValues: headers.map { key, value in
            if isSensitiveKey(key) {
                return (key, PayabliLogger.redactFully(value))
            }
            return (key, value)
        })
    }

    private static func redactedBodyString(_ body: Data?) -> String? {
        guard let body, !body.isEmpty else { return nil }

        do {
            let object = try JSONSerialization.jsonObject(with: body)
            let redacted = redactJSONValue(object, key: nil)
            let data = try PayInPaymentFlowJSONBody.data(
                from: PayInPaymentFlowJSONBody.normalizingCurrencyFields(in: redacted)
            )
            return String(data: data, encoding: .utf8)
        } catch {
            return "[REDACTED NON-JSON BODY; \(body.count) bytes]"
        }
    }

    private static func redactJSONValue(_ value: Any, key: String?) -> Any {
        if let key, isSensitiveKey(key) {
            return "[REDACTED]"
        }

        if let dictionary = value as? [String: Any] {
            return dictionary.reduce(into: [String: Any]()) { result, pair in
                result[pair.key] = redactJSONValue(pair.value, key: pair.key)
            }
        }

        if let array = value as? [Any] {
            return array.map { redactJSONValue($0, key: nil) }
        }

        return value
    }

    private static func isSensitiveKey(_ key: String) -> Bool {
        let normalized = key
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }

        let exactKeys: Set = [
            "authorization",
            "requesttoken",
            "accesstoken",
            "clientsecret",
            "cardnumber",
            "cardcvv",
            "cvv",
            "cardexp",
            "cardzip",
            "cardholder",
            "achaccount",
            "achrouting",
            "achholder",
            "accountnumber",
            "referenceid",
            "methodreferenceid",
            "routingnumber",
            "storedmethodid",
            "customerid",
            "customernumber",
            "billingemail",
            "billingphone",
            "billingaddress1",
            "billingaddress2",
            "billingcity",
            "billingstate",
            "billingzip",
            "shippingaddress1",
            "shippingaddress2",
            "shippingcity",
            "shippingstate",
            "shippingzip",
            "firstname",
            "lastname",
            "name",
            "email",
            "phone"
        ]
        if exactKeys.contains(normalized) {
            return true
        }

        return normalized.contains("secret") ||
            normalized.contains("token") ||
            normalized.contains("password") ||
            normalized.contains("account") ||
            normalized.contains("routing") ||
            normalized.contains("cardnumber") ||
            normalized.contains("cvv") ||
            normalized.contains("email") ||
            normalized.contains("phone") ||
            normalized.contains("address")
    }
}

extension PayabliPayInPaymentFlowDiagnostics {
    private static func diagnosticMessage(for error: Error) -> String {
        let message: String = if let payabliError = error as? any PayabliError {
            if let detail = payabliError.detail?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty, detail != payabliError.reason {
                "\(payabliError.reason) \(detail)"
            } else {
                payabliError.reason
            }
        } else {
            String(describing: error)
        }
        return PayabliPayInPaymentFlowSensitiveDataRedactor.redact(message)
    }
}

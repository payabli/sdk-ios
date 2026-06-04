import Foundation
import PayabliSDKCore

/// HTTP client for v2 MoneyIn transaction endpoints.
///
/// This client authenticates with the same one-off bearer-token pattern used by
/// a Pay In payment flow: host apps fetch a scoped token from their backend
/// before submission, and the SDK sends it as `Authorization: Bearer <token>`.
final class PayInPaymentFlowClient: Sendable {
    private let transport: any PayabliTransport
    private let accessTokenProvider: PayabliPayInPaymentFlowAccessTokenProvider
    private let baseURL: URL?
    private let diagnostics: PayabliPayInPaymentFlowDiagnostics

    init(
        transport: any PayabliTransport,
        accessTokenProvider: @escaping PayabliPayInPaymentFlowAccessTokenProvider,
        baseURL: URL? = nil,
        diagnostics: PayabliPayInPaymentFlowDiagnostics = .disabled
    ) {
        self.transport = transport
        self.accessTokenProvider = accessTokenProvider
        self.baseURL = baseURL
        self.diagnostics = diagnostics
    }

    func capture(
        entryPoint: String,
        request: PayabliPayInPaymentFlowRequest
    ) async throws -> PayabliPayInPaymentFlowResult {
        try await performTransaction(
            path: "/api/v2/MoneyIn/getpaid",
            entryPoint: entryPoint,
            request: request,
            allowsACHValidation: true
        )
    }

    func authorize(
        entryPoint: String,
        request: PayabliPayInPaymentFlowRequest
    ) async throws -> PayabliPayInPaymentFlowResult {
        guard request.paymentMethod.authorizationMethod != nil else {
            throw PayabliPayInPaymentFlowError.invalidInput("Only card data can be authorized.")
        }
        return try await performTransaction(
            path: "/api/v2/MoneyIn/authorize",
            entryPoint: entryPoint,
            request: request,
            allowsACHValidation: false
        )
    }

    func captureAuthorized(
        _ request: PayabliPayInPaymentFlowAuthorizedRequest
    ) async throws -> PayabliPayInPaymentFlowResult {
        let transId = request.transId.payabliCaptureTrimmed
        guard !transId.isEmpty else {
            throw PayabliPayInPaymentFlowError.invalidInput("Transaction ID is required.")
        }
        try request.paymentDetails.validate()

        let body = AuthorizedCaptureBody(paymentDetails: request.paymentDetails)
        let payabliRequest = try await authorizedRequest(
            path: "/api/v2/MoneyIn/capture/\(Self.pathComponent(transId))",
            query: [],
            idempotencyKey: nil,
            body: body
        )
        return try await perform(payabliRequest)
    }

    private func performTransaction(
        path: String,
        entryPoint: String,
        request: PayabliPayInPaymentFlowRequest,
        allowsACHValidation: Bool
    ) async throws -> PayabliPayInPaymentFlowResult {
        let entry = entryPoint.payabliCaptureTrimmed
        guard !entry.isEmpty else {
            throw PayabliPayInPaymentFlowError.invalidInput("Entrypoint is required.")
        }
        try request.paymentDetails.validate()
        try request.paymentMethod.validate(request.validation)

        let body = TransactionRequestBody(
            accountId: request.accountId?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty,
            customerData: request.customerData,
            entryPoint: entry,
            ipaddress: request.ipAddress?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty,
            orderDescription: request.orderDescription?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty,
            orderId: request.orderId?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty,
            paymentDetails: request.paymentDetails,
            paymentMethod: request.paymentMethod,
            source: request.source?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty,
            subdomain: request.subdomain?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty,
            subscriptionId: request.subscriptionId
        )
        let payabliRequest = try await authorizedRequest(
            path: path,
            query: request.queryItems(allowsACHValidation: allowsACHValidation),
            idempotencyKey: request.idempotencyKey,
            body: body
        )
        return try await perform(payabliRequest)
    }

    private func authorizedRequest(
        path: String,
        query: [URLQueryItem],
        idempotencyKey: String?,
        body: some Encodable
    ) async throws -> PayabliRequest {
        let accessToken = try await accessTokenProvider()
        let trimmedAccessToken = accessToken.payabliCaptureTrimmed
        guard !trimmedAccessToken.isEmpty else {
            throw PayabliPayInPaymentFlowError.missingAccessToken
        }

        var headers = ["Authorization": "Bearer \(trimmedAccessToken)"]
        if let idempotencyKey = idempotencyKey?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty {
            headers["idempotencyKey"] = idempotencyKey
        }

        var mergedHeaders = headers
        mergedHeaders["Content-Type"] = "application/json"

        return try PayabliRequest(
            method: .post,
            path: path,
            query: query,
            headers: mergedHeaders,
            body: PayInPaymentFlowJSONBody.encode(body)
        )
    }

    private func perform(_ request: PayabliRequest) async throws -> PayabliPayInPaymentFlowResult {
        diagnostics.logRequest(request, baseURL: baseURL)
        let start = Date()
        let response: PayabliResponse
        do {
            response = try await transport.perform(request)
        } catch {
            diagnostics.logFailure(
                error,
                request: request,
                baseURL: baseURL,
                durationMilliseconds: Date().timeIntervalSince(start) * 1000
            )
            throw error
        }
        diagnostics.logResponse(
            response,
            request: request,
            baseURL: baseURL,
            durationMilliseconds: Date().timeIntervalSince(start) * 1000
        )
        return try decodeResult(from: response)
    }

    private func decodeResult(from response: PayabliResponse) throws -> PayabliPayInPaymentFlowResult {
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode(PayabliPayInPaymentFlowAPIResponse.self, from: response.body) {
            guard decoded.isApproved else {
                throw PayabliPayInPaymentFlowError.transactionFailed(decoded.failure(httpStatusCode: response.statusCode))
            }
            return PayabliPayInPaymentFlowResult(apiResponse: decoded)
        }

        if let failure = decodeFailure(from: response, decoder: decoder) {
            throw PayabliPayInPaymentFlowError.transactionFailed(failure)
        }

        try mapPayabliHTTPError(response: response)
        throw PayabliGenericError(
            code: .decodingError,
            reason: "Failed to decode payment capture response"
        )
    }

    private func decodeFailure(
        from response: PayabliResponse,
        decoder: JSONDecoder
    ) -> PayabliPayInPaymentFlowFailure? {
        guard
            let envelope = try? decoder.decode(PayInPaymentFlowFailureEnvelope.self, from: response.body),
            envelope.isFailure(httpStatusCode: response.statusCode)
        else {
            return nil
        }

        return envelope.failure(httpStatusCode: response.statusCode)
    }

    private static func pathComponent(_ value: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        return value.addingPercentEncoding(withAllowedCharacters: allowed) ?? value
    }
}

private struct TransactionRequestBody: Encodable {
    let accountId: String?
    let customerData: PayabliPayInPaymentFlowCustomerData?
    let entryPoint: String
    let ipaddress: String?
    let orderDescription: String?
    let orderId: String?
    let paymentDetails: PayabliPayInPaymentFlowPaymentDetails
    let paymentMethod: PayabliPayInPaymentFlowPaymentMethod
    let source: String?
    let subdomain: String?
    let subscriptionId: Int64?
}

private struct AuthorizedCaptureBody: Encodable {
    let paymentDetails: PayabliPayInPaymentFlowPaymentDetails
}

private struct PayInPaymentFlowFailureEnvelope: Decodable {
    let isSuccess: Bool?
    let code: String?
    let reason: String?
    let explanation: String?
    let action: String?
    let status: Int?
    let title: String?
    let detail: String?
    let message: String?
    let error: String?
    let responseText: String?
    let responseCode: Int?
    let responseData: PayInPaymentFlowFailureResponseData?

    enum CodingKeys: String, CodingKey {
        case isSuccess
        case code
        case reason
        case explanation
        case action
        case status
        case title
        case detail
        case message
        case error
        case responseText
        case responseCode
        case responseData
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        isSuccess = try c.decodeIfPresent(Bool.self, forKey: .isSuccess)
        code = c.decodeLossyStringIfPresent(forKey: .code)
        reason = try c.decodeIfPresent(String.self, forKey: .reason)
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation)
        action = try c.decodeIfPresent(String.self, forKey: .action)
        status = c.decodeLossyIntIfPresent(forKey: .status)
        title = try c.decodeIfPresent(String.self, forKey: .title)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
        message = try c.decodeIfPresent(String.self, forKey: .message)
        error = try c.decodeIfPresent(String.self, forKey: .error)
        responseText = try c.decodeIfPresent(String.self, forKey: .responseText)
        responseCode = c.decodeLossyIntIfPresent(forKey: .responseCode)
        responseData = try c.decodeIfPresent(PayInPaymentFlowFailureResponseData.self, forKey: .responseData)
    }

    func isFailure(httpStatusCode: Int) -> Bool {
        if isSuccess == false {
            return true
        }
        if let code = code?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty {
            return !code.hasPrefix("A")
        }
        if !(200 ..< 300).contains(httpStatusCode), preferredMessage != nil {
            return true
        }
        return false
    }

    func failure(httpStatusCode: Int) -> PayabliPayInPaymentFlowFailure {
        PayabliPayInPaymentFlowFailure(
            code: code?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty ?? responseData?.resultCode?.payabliCaptureTrimmed
                .payabliCaptureNilIfEmpty,
            reason: reason?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
                ?? responseData?.resultText?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
                ?? title?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
                ?? responseText?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
                ?? message?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
                ?? error?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty,
            explanation: explanation?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
                ?? responseData?.explanation?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
                ?? detail?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
                ?? responseData?.detail?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty,
            action: action?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
                ?? responseData?.todoAction?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty,
            status: status ?? responseCode,
            detail: detail?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
                ?? responseData?.detail?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty,
            httpStatusCode: httpStatusCode
        )
    }

    private var preferredMessage: String? {
        explanation?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
            ?? responseData?.explanation?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
            ?? reason?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
            ?? responseData?.resultText?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
            ?? title?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
            ?? detail?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
            ?? responseData?.detail?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
            ?? responseText?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
            ?? message?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
            ?? error?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
    }
}

private struct PayInPaymentFlowFailureResponseData: Decodable {
    let resultCode: String?
    let resultText: String?
    let explanation: String?
    let todoAction: String?
    let detail: String?

    enum CodingKeys: String, CodingKey {
        case resultCode
        case resultText
        case explanation
        case todoAction
        case detail
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        resultCode = c.decodeLossyStringIfPresent(forKey: .resultCode)
        resultText = try c.decodeIfPresent(String.self, forKey: .resultText)
        explanation = try c.decodeIfPresent(String.self, forKey: .explanation)
        todoAction = try c.decodeIfPresent(String.self, forKey: .todoAction)
        detail = try c.decodeIfPresent(String.self, forKey: .detail)
    }
}

private extension PayabliPayInPaymentFlowRequest {
    func queryItems(allowsACHValidation: Bool) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        if allowsACHValidation {
            appendBool(achValidation, name: "achValidation", to: &items)
        }
        appendBool(forceCustomerCreation, name: "forceCustomerCreation", to: &items)
        return items
    }

    func appendBool(_ value: Bool?, name: String, to items: inout [URLQueryItem]) {
        guard let value else { return }
        items.append(URLQueryItem(name: name, value: value ? "true" : "false"))
    }
}

private extension KeyedDecodingContainer {
    func decodeLossyStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Int64.self, forKey: key) {
            return String(value)
        }
        if let value = try? decodeIfPresent(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    func decodeLossyIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decodeIfPresent(Int.self, forKey: key) {
            return value
        }
        if let value = try? decodeIfPresent(String.self, forKey: key) {
            return Int(value)
        }
        return nil
    }
}

import Foundation
import PayabliSDKCore

/// HTTP client for v2 MoneyIn transaction endpoints.
///
/// It builds requests and reads responses. The credential is attached by the chain inside the
/// transport, so nothing here holds a token or a token source.
final class PayInPaymentFlowClient: Sendable {
    private let transport: any PayabliTransport
    private let baseURL: URL?
    private let diagnostics: PayabliPayInPaymentFlowDiagnostics

    init(
        transport: any PayabliTransport,
        baseURL: URL? = nil,
        diagnostics: PayabliPayInPaymentFlowDiagnostics = .disabled
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.diagnostics = diagnostics
    }

    func capture(
        entryPoint: String,
        request: PayabliPayInPaymentFlowRequest,
        idempotencyKey: String
    ) async throws -> PayabliPayInPaymentFlowResult {
        try await performTransaction(
            path: "/api/v2/MoneyIn/getpaid",
            entryPoint: entryPoint,
            request: request,
            idempotencyKey: idempotencyKey,
            allowsACHValidation: true
        )
    }

    func authorize(
        entryPoint: String,
        request: PayabliPayInPaymentFlowRequest,
        idempotencyKey: String
    ) async throws -> PayabliPayInPaymentFlowResult {
        guard request.paymentMethod.authorizationMethod != nil else {
            throw PayabliPayInPaymentFlowError.invalidInput("Only card data can be authorized.")
        }
        return try await performTransaction(
            path: "/api/v2/MoneyIn/authorize",
            entryPoint: entryPoint,
            request: request,
            idempotencyKey: idempotencyKey,
            allowsACHValidation: false
        )
    }

    func captureAuthorized(
        _ request: PayabliPayInPaymentFlowAuthorizedRequest,
        idempotencyKey: String
    ) async throws -> PayabliPayInPaymentFlowResult {
        let transId = request.transId.payabliCaptureTrimmed
        guard !transId.isEmpty else {
            throw PayabliPayInPaymentFlowError.invalidInput("Transaction ID is required.")
        }
        try request.paymentDetails.validate()

        let body = AuthorizedCaptureBody(paymentDetails: request.paymentDetails)
        let payabliRequest = try buildRequest(
            path: "/api/v2/MoneyIn/capture/\(Self.pathComponent(transId))",
            query: [],
            idempotencyKey: idempotencyKey,
            body: body
        )
        return try await perform(payabliRequest, retryKey: idempotencyKey)
    }

    private func performTransaction(
        path: String,
        entryPoint: String,
        request: PayabliPayInPaymentFlowRequest,
        idempotencyKey: String,
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
        let payabliRequest = try buildRequest(
            path: path,
            query: request.queryItems(allowsACHValidation: allowsACHValidation),
            idempotencyKey: idempotencyKey,
            body: body
        )
        return try await perform(payabliRequest, retryKey: idempotencyKey)
    }

    /// Builds the request. The transport's chain attaches the credential and the content type.
    ///
    /// The idempotency key is set here because the chain runs once per attempt, and a key minted
    /// there would differ on a replay.
    private func buildRequest(
        path: String,
        query: [URLQueryItem],
        idempotencyKey: String?,
        body: some Encodable
    ) throws -> PayabliRequest {
        var headers: [String: String] = [:]
        if let idempotencyKey {
            headers["idempotencyKey"] = try Self.sendableKey(idempotencyKey)
        }

        return try PayabliRequest(
            method: .post,
            path: path,
            query: query,
            headers: headers,
            body: PayInPaymentFlowJSONBody.encode(body)
        )
    }

    /// The key as it will be sent, or a refusal.
    ///
    /// A value that is blank once trimmed is refused rather than dropped. Dropping it sends a
    /// money-moving request with no duplicate protection to a caller who set a key and believes it is
    /// protected. A value that cannot sit in a header is refused for the reason `isHeaderSafe` exists:
    /// `URLRequest.setValue` mangles a header holding a carriage return rather than reporting it, so the
    /// request would go out unprotected and the failure would name something else.
    private static func sendableKey(_ key: String) throws -> String {
        let trimmed = key.payabliCaptureTrimmed
        guard !trimmed.isBlank else {
            throw PayabliPayInPaymentFlowError.invalidInput("The idempotency key cannot be blank.")
        }
        guard trimmed.isHeaderSafe else {
            throw PayabliPayInPaymentFlowError
                .invalidInput("The idempotency key may contain printable ASCII only.")
        }
        return trimmed
    }

    /// Whether a failure leaves the outcome of a money-moving request open.
    ///
    /// The sibling platform draws this line and these are its classes: a cancellation, a network
    /// failure, a 5xx, a response that could not be decoded, and anything unexpected. In each the
    /// payment may already have been taken.
    ///
    /// A decline, a validation refusal, a refused or expired credential and a burned session are all
    /// answers, so the outcome is known and a retry is a new payment. So is a repeat the service
    /// recognised and refused, which arrives as its own status and is what a key existing at all
    /// produces: reporting it as unknown would tell a caller to resend the key that provoked it.
    private static func leavesOutcomeUnknown(_ failure: any Error) -> Bool {
        switch failure {
        case is PayabliPayInPaymentFlowError:
            return false
        case let payment as PayabliPaymentError:
            if case .server = payment {
                return true
            }
            return false
        case let generic as PayabliGenericError:
            switch generic.code {
            case .networkError, .decodingError, .userCancelled:
                return true
            case .missingToken, .tokenExpired, .tokenMalformed, .invalidSignature,
                 .permissionDenied, .sessionBurned, .invalidConfiguration, .validation:
                return false
            case .unknown:
                // Every other status, the recognised repeat among them. Known: the service answered.
                return false
            }
        default:
            return true
        }
    }

    private func perform(
        _ request: PayabliRequest,
        retryKey: String? = nil
    ) async throws -> PayabliPayInPaymentFlowResult {
        do {
            return try await send(request)
        } catch let failure as PayInProviderFailure {
            // The credential was never minted, so nothing was sent: the outcome is known and there is
            // no key to report. The host gets the error it threw, unwrapped and unwrapped only here.
            throw failure.underlying
        } catch {
            guard let retryKey, Self.leavesOutcomeUnknown(error) else { throw error }
            throw PayabliPayInPaymentFlowError.submissionInterrupted(
                retryKey: retryKey,
                underlying: error
            )
        }
    }

    private func send(_ request: PayabliRequest) async throws -> PayabliPayInPaymentFlowResult {
        diagnostics.logRequest(request, baseURL: baseURL)
        let start = Date()
        let response: PayabliResponse
        do {
            response = try await transport.perform(request)
        } catch let failure as PayInProviderFailure {
            // Not recorded: the host's own error can name its backend, and the sink renders a non-SDK
            // error whole. Rethrown intact so the caller below can tell it apart; it is unwrapped there.
            throw failure
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
        let failureCode = Self.firstNonEmpty(code, responseData?.resultCode)
        let failureReason = Self.firstNonEmpty(
            reason,
            responseData?.resultText,
            title,
            responseText,
            message,
            error
        )
        let failureExplanation = Self.firstNonEmpty(
            explanation,
            responseData?.explanation,
            detail,
            responseData?.detail
        )
        let failureAction = Self.firstNonEmpty(action, responseData?.todoAction)
        let failureDetail = Self.firstNonEmpty(detail, responseData?.detail)

        return PayabliPayInPaymentFlowFailure(
            code: failureCode,
            reason: failureReason,
            explanation: failureExplanation,
            action: failureAction,
            status: status ?? responseCode,
            detail: failureDetail,
            httpStatusCode: httpStatusCode
        )
    }

    private var preferredMessage: String? {
        Self.firstNonEmpty(
            explanation,
            responseData?.explanation,
            reason,
            responseData?.resultText,
            title,
            detail,
            responseData?.detail,
            responseText,
            message,
            error
        )
    }

    private static func firstNonEmpty(_ values: String?...) -> String? {
        for value in values {
            if let trimmed = value?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty {
                return trimmed
            }
        }
        return nil
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

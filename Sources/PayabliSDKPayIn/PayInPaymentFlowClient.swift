import Foundation
import PayabliSDKCore

/// HTTP client for v2 MoneyIn transaction endpoints.
///
/// It builds requests and reads responses. The credential is attached by the chain inside the
/// transport, so nothing here holds a token or a token source.
final class PayInPaymentFlowClient: Sendable {
    private let transport: any PayabliTransport

    init(transport: any PayabliTransport) {
        self.transport = transport
    }

    func capture(
        entryPoint: String,
        request: PayabliPayInRequest,
        idempotencyKey: String
    ) async throws -> PayabliPayInResult {
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
        request: PayabliPayInRequest,
        idempotencyKey: String
    ) async throws -> PayabliPayInResult {
        guard request.paymentMethod.isAuthorizable else {
            throw PayabliPayInError.invalidInput("This payment method cannot be authorized.")
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
        _ request: PayabliPayInAuthorizedRequest,
        idempotencyKey: String
    ) async throws -> PayabliPayInResult {
        let transId = request.transId.payabliCaptureTrimmed
        guard !transId.isEmpty else {
            throw PayabliPayInError.invalidInput("Transaction ID is required.")
        }
        try request.paymentDetails.validate()

        let body = AuthorizedCaptureBody(paymentDetails: request.paymentDetails)
        let payabliRequest = try buildRequest(
            path: "/api/v2/MoneyIn/capture/\(PercentEncoding.segment(transId))",
            query: [],
            idempotencyKey: idempotencyKey,
            body: body
        )
        // Whether a key went out, not which one: nothing reports a key, and `perform` needs only to
        // know that this route carries one so a failure that leaves the outcome open says so.
        return try await perform(payabliRequest, carriesKey: payabliRequest.headers[payabliIdempotencyKeyHeader] != nil)
    }

    /// Reverses a transaction, releasing an authorization's hold or undoing a capture that has not
    /// settled.
    ///
    /// The route carries the identifier in its path and takes no body, so there is no partial void.
    ///
    /// - Parameter transId: the transaction to reverse, as ``PayabliPayInTransaction/paymentTransId`` reported it.
    /// - Parameter idempotencyKey: the key to carry as the `idempotencyKey` header, trimmed before it is set.
    /// - Returns: the result the service sent.
    func void(
        transId: String,
        idempotencyKey: String
    ) async throws -> PayabliPayInResult {
        let transId = transId.payabliCaptureTrimmed
        guard !transId.isEmpty else {
            throw PayabliPayInError.invalidInput("Transaction ID is required.")
        }
        // `.` and `..` are unreserved, so the encoder passes them through as themselves and the
        // identifier names a route rather than a transaction. Refused here because whether a value is
        // usable is the caller's question rather than the encoder's.
        guard transId != ".", transId != ".." else {
            throw PayabliPayInError.invalidInput("Transaction ID is required.")
        }

        let payabliRequest = try buildRequest(
            path: "/api/v2/MoneyIn/void/\(PercentEncoding.segment(transId))",
            query: [],
            idempotencyKey: idempotencyKey
        )
        // Whether a key went out, not which one: nothing reports a key, and `perform` needs only to
        // know that this route carries one so a failure that leaves the outcome open says so.
        return try await perform(payabliRequest, carriesKey: payabliRequest.headers[payabliIdempotencyKeyHeader] != nil)
    }

    /// Reads a transaction back by its identifier.
    ///
    /// Moves no money, so it sends no key and a failure arrives as itself, never as an unknown outcome.
    ///
    /// - Parameter transId: the transaction to read.
    /// - Returns: the transaction, carrying only the fields ``TransactionDetailsRecord`` reads.
    func details(transId: String) async throws -> PayabliPayInTransaction {
        let transId = transId.payabliCaptureTrimmed
        guard !transId.isEmpty, transId != ".", transId != ".." else {
            throw PayabliPayInError.invalidInput("Transaction ID is required.")
        }
        let request = PayabliRequest(
            method: .get,
            path: "/api/MoneyIn/details/\(PercentEncoding.segment(transId))",
            isCallerRefusal: { $0.statusCode == 401 && Self.legacyCode(of: $0) == Self.callerMayNotRead }
        )
        let response = try await transport.perform(request)
        return try Self.decodeDetails(from: response, asked: transId)
    }

    /// The code a details refusal carries when the transaction is under a paypoint this caller may not read.
    private static let callerMayNotRead = 9001
    /// The code a details refusal carries when no transaction is visible under the identifier.
    private static let noSuchTransaction = 7001

    private static func decodeDetails(
        from response: PayabliResponse,
        asked transId: String
    ) throws -> PayabliPayInTransaction {
        switch (response.statusCode, legacyCode(of: response)) {
        case (401, callerMayNotRead):
            throw catalogRefusal(.permissionDenied)
        case (400, noSuchTransaction):
            throw catalogRefusal(.transactionNotFound)
        default:
            try mapPayabliHTTPError(response: response)
        }
        // The decoding error is not attached: it quotes the body it rejected.
        guard let record = try? JSONDecoder().decode(TransactionDetailsRecord.self, from: response.body) else {
            throw PayabliGenericError(type: .decodingError, reason: "Failed to decode the transaction")
        }
        guard record.paymentTransId == transId else {
            throw PayabliGenericError(type: .decodingError, reason: "The answer names a different transaction")
        }
        return record.transaction
    }

    /// A refusal whose reason is the catalog's own text for `type`, so every platform words it the same.
    ///
    /// - Parameter type: the refusal's type, which picks the catalog's text.
    /// - Returns: the refusal, carrying the catalog's text as its reason.
    private static func catalogRefusal(_ type: PayabliErrorType) -> PayabliGenericError {
        PayabliGenericError(type: type, reason: PayabliGenericError(type: type, reason: "").message)
    }

    /// The numeric `responseCode` of the older envelope, or `nil` when the body carries none.
    ///
    /// - Parameter response: the answer being classified, whose body is read for the code.
    /// - Returns: the numeric `responseCode`, or nil when the body carries none.
    private static func legacyCode(of response: PayabliResponse) -> Int? {
        try? JSONDecoder().decode(LegacyRefusal.self, from: response.body).responseCode
    }

    private func performTransaction(
        path: String,
        entryPoint: String,
        request: PayabliPayInRequest,
        idempotencyKey: String,
        allowsACHValidation: Bool
    ) async throws -> PayabliPayInResult {
        let entry = entryPoint.payabliCaptureTrimmed
        guard !entry.isEmpty else {
            throw PayabliPayInError.invalidInput("Entrypoint is required.")
        }
        try request.paymentDetails.validate()
        try request.paymentMethod.validate(request.options.validation)

        let body = TransactionRequestBody(
            accountId: request.options.accountId?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty,
            customerData: request.options.customerData,
            entryPoint: entry,
            ipaddress: request.options.ipAddress?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty,
            orderDescription: request.options.orderDescription?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty,
            orderId: request.options.orderId?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty,
            paymentDetails: request.paymentDetails,
            paymentMethod: request.paymentMethod,
            source: request.options.source?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty,
            subdomain: request.options.subdomain?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty,
            subscriptionId: request.options.subscriptionId
        )
        let payabliRequest = try buildRequest(
            path: path,
            query: request.queryItems(allowsACHValidation: allowsACHValidation),
            idempotencyKey: idempotencyKey,
            body: body
        )
        // Whether a key went out, not which one: nothing reports a key, and `perform` needs only to
        // know that this route carries one so a failure that leaves the outcome open says so.
        return try await perform(payabliRequest, carriesKey: payabliRequest.headers[payabliIdempotencyKeyHeader] != nil)
    }

    /// Builds the request. The transport's chain attaches the credential and the content type.
    ///
    /// The idempotency key is set here because the chain runs once per attempt, and a key minted
    /// there would differ on a replay.
    ///
    /// - Parameter path: the route's path, as `/api/v2/MoneyIn/getpaid`.
    /// - Parameter query: the query items the route reads, such as `achValidation`.
    /// - Parameter idempotencyKey: the key to carry as the `idempotencyKey` header; nil sends none.
    /// - Parameter body: the request's body, encoded as the route reads it.
    /// - Returns: the request the transport sends.
    private func buildRequest(
        path: String,
        query: [URLQueryItem],
        idempotencyKey: String?,
        body: some Encodable
    ) throws -> PayabliRequest {
        try PayabliRequest(
            method: .post,
            path: path,
            query: query,
            headers: Self.headers(idempotencyKey: idempotencyKey),
            body: PayInPaymentFlowJSONBody.encode(body)
        )
    }

    /// Builds a request for a route that carries everything it needs in its path.
    ///
    /// The body stays absent rather than being an empty object: the two are different requests, and
    /// only the first is what the route was measured against.
    ///
    /// - Parameter path: the route's path, as `/api/v2/MoneyIn/void/<transId>`.
    /// - Parameter query: the query items the route reads, empty on these routes.
    /// - Parameter idempotencyKey: the key to carry as the `idempotencyKey` header; nil sends none.
    /// - Returns: the request the transport sends, with no body.
    private func buildRequest(
        path: String,
        query: [URLQueryItem],
        idempotencyKey: String?
    ) throws -> PayabliRequest {
        try PayabliRequest(
            method: .post,
            path: path,
            query: query,
            headers: Self.headers(idempotencyKey: idempotencyKey)
        )
    }

    private static func headers(idempotencyKey: String?) throws -> [String: String] {
        guard let idempotencyKey else { return [:] }
        return [payabliIdempotencyKeyHeader: try sendableKey(idempotencyKey)]
    }

    /// The key as it will be sent, or a refusal.
    ///
    /// A key that is blank once trimmed, or cannot sit in a header, is refused rather than dropped: a
    /// caller that set one is never sent a request the header does not protect.
    ///
    /// - Parameter key: the key as the caller set it.
    /// - Returns: the trimmed key, as the `idempotencyKey` header carries it.
    /// - Throws: ``PayabliPayInError/invalidInput(_:)`` when the key is blank once trimmed or cannot sit in a header.
    private static func sendableKey(_ key: String) throws -> String {
        let trimmed = key.payabliCaptureTrimmed
        guard !trimmed.isBlank else {
            throw PayabliPayInError.invalidInput("The idempotency key cannot be blank.")
        }
        guard trimmed.isHeaderSafe else {
            throw PayabliPayInError
                .invalidInput("The idempotency key may contain printable ASCII only.")
        }
        return trimmed
    }

    /// Whether a failure leaves a money-moving request's outcome open, so it may have taken the payment.
    ///
    /// Open: a cancellation, a network failure, a 5xx, an unreadable answer, a `409` and anything unclassified.
    /// A decline, a validation refusal, a rate limit and a refused credential are answers.
    ///
    /// - Parameter failure: the failure a send ended in, classified by its ``PayabliErrorType``.
    /// - Returns: whether the failure leaves the outcome open.
    private static func leavesOutcomeUnknown(_ failure: any Error) -> Bool {
        guard let code = (failure as? any PayabliError)?.type else {
            // Not this SDK's error at all, so nothing classified it and nothing can say it settled.
            return true
        }
        switch code {
        case .networkError, .decodingError, .userCancelled, .serverError, .unknown, .conflict, .retryRefused,
             .tapNotCompleted, .paymentOutcomeUnknown, .paymentNotClosed, .chargeNotFinished:
            return true
        case .paymentDeclined, .rateLimited, .missingToken, .tokenExpired,
             .tokenMalformed, .tokenProviderFailed, .invalidSignature, .permissionDenied,
             .sessionBurned, .invalidConfiguration, .validation,
             .deviceKeyUnavailable, .deviceSetupUnsupported, .sdkInternalError, .sessionNotInitialized,
             .deviceServicesOutdated,
             .devicePendingActivation, .deviceSetupRequired, .deviceSetupRefused, .deviceSetupUnavailable,
             .deviceSetupNotConfigured, .entryPointRefused, .readerCredentialsUnusable, .deviceOSUnsupported,
             .deviceHardwareUnsupported, .termsNotAccepted, .cardPresentNotEnabled, .readerDeviceRefused,
             .readerUnavailable, .readerSessionExpired, .paymentNotOpened, .cardDeclined, .activationCodeMalformed,
             .activationCodeIncorrect, .activationCodeExpired, .activationAttemptsExhausted, .activationCodeNotIssued,
             .deviceNotPending, .terminalNotReady, .tooManyOpenCharges, .paymentNotHeld, .deviceIdentityUnavailable,
             .paymentNotTaken, .transactionNotFound, .retryNotSamePayment, .paymentReferenceOpen, .contactlessDisabled:
            return false
        }
    }

    private func perform(
        _ request: PayabliRequest,
        carriesKey: Bool = false
    ) async throws -> PayabliPayInResult {
        var answer: PayabliResponse?
        do {
            let response = try await transport.perform(request)
            answer = response
            return try decodeResult(from: response)
        } catch {
            let refusedKey = error is IdempotencyCheckRefusal
            let failure: any Error = if refusedKey {
                PayabliGenericError(type: .conflict, reason: "Conflict (409)")
            } else if PayInInterruption.isCancellation(error) {
                CancellationError()
            } else {
                error
            }
            let conflict = answer?.statusCode == 409
            // A credential that was never obtained arrives as `.tokenExpired` or
            // `.tokenProviderFailed`, both of which `leavesOutcomeUnknown` answers false for: nothing
            // was sent, so the outcome is known and there is no key to report.
            guard carriesKey, conflict || Self.leavesOutcomeUnknown(failure) else { throw failure }
            let interruption = PayabliPayInError.submissionInterrupted(
                type: conflict ? .conflict : PayInInterruption.type(of: failure),
                causeType: RedactedCause(failure).originalType,
                paymentTransId: Self.namedTransaction(in: answer),
                paymentReference: nil
            )
            throw PayInOpenOutcome(interruption: interruption, cause: failure, refusedKey: refusedKey)
        }
    }

    /// The `data.paymentTransId` an answer that left the outcome open names, if any. Only that field is
    /// decoded, so an answer that could not otherwise be read still names its transaction.
    ///
    /// - Parameter answer: the answer the failed send got, nil when there was none.
    /// - Returns: the transaction the answer names, trimmed, or nil when it names none.
    private static func namedTransaction(in answer: PayabliResponse?) -> String? {
        guard let answer else { return nil }
        let decoded = try? JSONDecoder().decode(NamedTransaction.self, from: answer.body)
        return decoded?.data?.paymentTransId?.payabliCaptureTrimmed.payabliCaptureNilIfEmpty
    }

    private func decodeResult(from response: PayabliResponse) throws -> PayabliPayInResult {
        if response.statusCode == 409, !Self.isJSONObject(response.body) {
            throw IdempotencyCheckRefusal()
        }
        // First, because the envelope decodes this body too and keeps none of the fields it names.
        if response.statusCode == 400 {
            try mapPayabliHTTPError(response: response)
        }
        let decoder = JSONDecoder()
        if let decoded = try? decoder.decode(PayabliPayInAPIResponse.self, from: response.body) {
            guard decoded.isApproved, response.statusCode != 409 else {
                throw PayabliPayInError.transactionFailed(decoded.failure(httpStatusCode: response.statusCode))
            }
            return PayabliPayInResult(apiResponse: decoded)
        }

        if let failure = decodeFailure(from: response, decoder: decoder) {
            throw PayabliPayInError.transactionFailed(failure)
        }

        try mapPayabliHTTPError(response: response)
        throw PayabliGenericError(
            type: .decodingError,
            reason: "Failed to decode payment capture response"
        )
    }

    private static func isJSONObject(_ body: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: body)) is [String: Any]
    }

    private func decodeFailure(
        from response: PayabliResponse,
        decoder: JSONDecoder
    ) -> PayabliPayInFailure? {
        guard
            let envelope = try? decoder.decode(PayInPaymentFlowFailureEnvelope.self, from: response.body),
            envelope.isFailure(httpStatusCode: response.statusCode)
        else {
            return nil
        }

        return envelope.failure(httpStatusCode: response.statusCode)
    }
}

/// The one field an unknown outcome keeps from the answer.
private struct NamedTransaction: Decodable {
    struct Payload: Decodable {
        let paymentTransId: String?
    }

    let data: Payload?
}

/// A 409 whose body is not a JSON object, which only the check that refuses a key it has already seen sends.
private struct IdempotencyCheckRefusal: Error {}

/// A money-moving request whose outcome is open, for the facade to report once it knows which key was sent.
struct PayInOpenOutcome: Error {
    /// The failure as a caller receives it when nothing else applies.
    let interruption: PayabliPayInError
    /// What failed, before it was read as an open outcome.
    let cause: any Error
    /// The service refused the key because it had already seen it.
    let refusedKey: Bool
}

private struct TransactionRequestBody: Encodable {
    let accountId: String?
    let customerData: PayabliPayInCustomerData?
    let entryPoint: String
    let ipaddress: String?
    let orderDescription: String?
    let orderId: String?
    let paymentDetails: PayabliPayInPaymentDetails
    let paymentMethod: PayabliPayInPaymentMethod
    let source: String?
    let subdomain: String?
    let subscriptionId: Int64?
}

private struct AuthorizedCaptureBody: Encodable {
    let paymentDetails: PayabliPayInPaymentDetails
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

    func failure(httpStatusCode: Int) -> PayabliPayInFailure {
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

        return PayabliPayInFailure(
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

private extension PayabliPayInRequest {
    func queryItems(allowsACHValidation: Bool) -> [URLQueryItem] {
        var items: [URLQueryItem] = []
        if allowsACHValidation {
            appendBool(options.achValidation, name: "achValidation", to: &items)
        }
        appendBool(options.forceCustomerCreation, name: "forceCustomerCreation", to: &items)
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

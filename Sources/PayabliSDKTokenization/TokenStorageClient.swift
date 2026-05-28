import Foundation
import PayabliSDKCore

/// HTTP client for `POST /api/TokenStorage/add`.
///
/// This endpoint authenticates with a server-side bearer token fetched from
/// the host application's backend. This client intentionally uses a raw
/// `PayabliTransport` instead of `PayabliSession.transport` because
/// tokenization owns the one-off access-token fetch before submit.
public final class TokenStorageClient: Sendable {
    private let transport: any PayabliTransport
    private let accessTokenProvider: PayabliTokenizationAccessTokenProvider
    private let baseURL: URL?
    private let diagnostics: PayabliTokenizationDiagnostics

    public init(
        transport: any PayabliTransport,
        accessTokenProvider: @escaping PayabliTokenizationAccessTokenProvider,
        baseURL: URL? = nil,
        diagnostics: PayabliTokenizationDiagnostics = .disabled
    ) {
        self.transport = transport
        self.accessTokenProvider = accessTokenProvider
        self.baseURL = baseURL
        self.diagnostics = diagnostics
    }

    public func addMethod(
        entryPoint: String,
        paymentMethod: PayabliTokenizationPaymentMethod,
        options: PayabliTokenizationOptions = PayabliTokenizationOptions()
    ) async throws -> PayabliTokenizedMethod {
        let entry = entryPoint.trimmed
        guard !entry.isEmpty else {
            throw PayabliTokenizationError.invalidInput("Entrypoint is required.")
        }
        try paymentMethod.validate(options.validation)

        let accessToken = try await accessTokenProvider()
        let trimmedAccessToken = accessToken.trimmed
        guard !trimmedAccessToken.isEmpty else {
            throw PayabliTokenizationError.missingAccessToken
        }

        let request = try addMethodRequest(
            entryPoint: entry,
            paymentMethod: paymentMethod,
            options: options,
            accessToken: trimmedAccessToken
        )
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
        if let failure = decodeTokenizationFailure(from: response) {
            throw PayabliTokenizationError.tokenizationFailed(failure)
        }
        try mapPayabliHTTPError(response: response)
        return try decodeTokenizedMethod(from: response)
    }

    private func addMethodRequest(
        entryPoint: String,
        paymentMethod: PayabliTokenizationPaymentMethod,
        options: PayabliTokenizationOptions,
        accessToken: String
    ) throws -> PayabliRequest {
        var headers = ["Authorization": "Bearer \(accessToken)"]
        if let idempotencyKey = options.idempotencyKey?.trimmed.nilIfEmpty {
            headers["idempotencyKey"] = idempotencyKey
        }

        return try PayabliRequest.json(
            method: .post,
            path: "/api/TokenStorage/add",
            query: options.queryItems,
            headers: headers,
            jsonBody: TokenStorageAddMethodBody(
                customerData: options.customerData,
                entryPoint: entryPoint,
                fallbackAuth: options.fallbackAuth,
                fallbackAuthAmount: options.fallbackAuthAmount,
                methodDescription: options.methodDescription?.trimmed.nilIfEmpty,
                paymentMethod: paymentMethod,
                vendorData: options.vendorData,
                source: options.source?.trimmed.nilIfEmpty,
                subdomain: options.subdomain?.trimmed.nilIfEmpty
            )
        )
    }

    private func decodeTokenizedMethod(from response: PayabliResponse) throws -> PayabliTokenizedMethod {
        let decoder = JSONDecoder()
        do {
            let decoded = try decoder.decode(PayabliTokenizationAPIResponse.self, from: response.body)
            let approved = decoded.isSuccess == true || decoded.responseData?.resultCode == 1
            guard approved else {
                throw PayabliTokenizationError.tokenizationFailed(decoded.failure(httpStatusCode: response.statusCode))
            }
            return PayabliTokenizedMethod(
                storedMethodId: decoded.responseData?.referenceId,
                methodReferenceId: decoded.responseData?.methodReferenceId,
                resultCode: decoded.responseData?.resultCode,
                resultText: decoded.responseData?.resultText,
                customerId: decoded.responseData?.customerId,
                responseText: decoded.responseText,
                apiResponse: decoded
            )
        } catch let error as PayabliTokenizationError {
            throw error
        } catch {
            throw PayabliGenericError(
                code: .decodingError,
                reason: "Failed to decode tokenization response",
                underlying: error
            )
        }
    }

    private func decodeTokenizationFailure(from response: PayabliResponse) -> PayabliTokenizationFailure? {
        let decoded = try? JSONDecoder().decode(PayabliTokenizationAPIResponse.self, from: response.body)
        guard let decoded, decoded.isSuccess == false else { return nil }
        return decoded.failure(httpStatusCode: response.statusCode)
    }
}

private struct TokenStorageAddMethodBody: Encodable {
    let customerData: PayabliTokenizationCustomerData?
    let entryPoint: String
    let fallbackAuth: Bool?
    let fallbackAuthAmount: Int?
    let methodDescription: String?
    let paymentMethod: PayabliTokenizationPaymentMethod
    let vendorData: PayabliTokenizationVendorData?
    let source: String?
    let subdomain: String?
}

private extension PayabliTokenizationOptions {
    var queryItems: [URLQueryItem] {
        var items: [URLQueryItem] = []
        appendBool(achValidation, name: "achValidation", to: &items)
        appendBool(createAnonymous, name: "createAnonymous", to: &items)
        appendBool(forceCustomerCreation, name: "forceCustomerCreation", to: &items)
        appendBool(temporary, name: "temporary", to: &items)
        return items
    }

    func appendBool(_ value: Bool?, name: String, to items: inout [URLQueryItem]) {
        guard let value else { return }
        items.append(URLQueryItem(name: name, value: value ? "true" : "false"))
    }
}

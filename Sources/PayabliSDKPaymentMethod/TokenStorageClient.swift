import Foundation
import PayabliSDKCore

/// HTTP client for `POST /api/TokenStorage/add`.
///
/// This endpoint authenticates with a server-side bearer token fetched from
/// the host application's backend. This client intentionally uses a raw
/// `PayabliTransport` instead of `PayabliSession.transport` because
/// the payment method component owns the one-off access-token fetch before submit.
final class TokenStorageClient: Sendable {
    private let transport: any PayabliTransport
    private let accessTokenProvider: PayabliPaymentMethodAccessTokenProvider
    private let baseURL: URL?
    private let diagnostics: PayabliPaymentMethodDiagnostics

    init(
        transport: any PayabliTransport,
        accessTokenProvider: @escaping PayabliPaymentMethodAccessTokenProvider,
        baseURL: URL? = nil,
        diagnostics: PayabliPaymentMethodDiagnostics = .disabled
    ) {
        self.transport = transport
        self.accessTokenProvider = accessTokenProvider
        self.baseURL = baseURL
        self.diagnostics = diagnostics
    }

    func addMethod(
        entryPoint: String,
        paymentMethod: PayabliPaymentMethodInput,
        options: PayabliPaymentMethodOptions = PayabliPaymentMethodOptions()
    ) async throws -> PayabliStoredPaymentMethod {
        let entry = entryPoint.trimmed
        guard !entry.isEmpty else {
            throw PayabliPaymentMethodError.invalidInput("Entrypoint is required.")
        }
        try paymentMethod.validate(options.validation)

        let accessToken = try await accessTokenProvider()
        let trimmedAccessToken = accessToken.trimmed
        guard !trimmedAccessToken.isEmpty else {
            throw PayabliPaymentMethodError.missingAccessToken
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
        if let failure = decodePaymentMethodFailure(from: response) {
            throw PayabliPaymentMethodError.saveFailed(failure)
        }
        try mapPayabliHTTPError(response: response)
        return try decodeStoredPaymentMethod(from: response)
    }

    private func addMethodRequest(
        entryPoint: String,
        paymentMethod: PayabliPaymentMethodInput,
        options: PayabliPaymentMethodOptions,
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

    private func decodeStoredPaymentMethod(from response: PayabliResponse) throws -> PayabliStoredPaymentMethod {
        let decoder = JSONDecoder()
        do {
            let decoded = try decoder.decode(PayabliPaymentMethodAPIResponse.self, from: response.body)
            let approved = decoded.isSuccess == true || decoded.responseData?.resultCode == 1
            guard approved else {
                throw PayabliPaymentMethodError.saveFailed(decoded.failure(httpStatusCode: response.statusCode))
            }
            return PayabliStoredPaymentMethod(
                storedMethodId: decoded.responseData?.referenceId,
                methodReferenceId: decoded.responseData?.methodReferenceId,
                resultCode: decoded.responseData?.resultCode,
                resultText: decoded.responseData?.resultText,
                customerId: decoded.responseData?.customerId,
                responseText: decoded.responseText,
                apiResponse: decoded
            )
        } catch let error as PayabliPaymentMethodError {
            throw error
        } catch {
            throw PayabliGenericError(
                code: .decodingError,
                reason: "Failed to decode payment method response",
                underlying: error
            )
        }
    }

    private func decodePaymentMethodFailure(from response: PayabliResponse) -> PayabliPaymentMethodFailure? {
        let decoded = try? JSONDecoder().decode(PayabliPaymentMethodAPIResponse.self, from: response.body)
        guard let decoded, decoded.isSuccess == false else { return nil }
        return decoded.failure(httpStatusCode: response.statusCode)
    }
}

private struct TokenStorageAddMethodBody: Encodable {
    let customerData: PayabliPaymentMethodCustomerData?
    let entryPoint: String
    let fallbackAuth: Bool?
    let fallbackAuthAmount: Int?
    let methodDescription: String?
    let paymentMethod: PayabliPaymentMethodInput
    let vendorData: PayabliPaymentMethodVendorData?
    let source: String?
    let subdomain: String?
}

private extension PayabliPaymentMethodOptions {
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

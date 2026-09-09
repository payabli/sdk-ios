import Foundation
import PayabliSDKCore

/// HTTP client for `POST /api/TokenStorage/add`.
///
/// It builds the request and reads the response. The credential is attached by the chain inside the
/// transport, so nothing here holds a token or a token source. That transport carries no 401
/// recovery: this surface's credential comes from a per-call provider, not from a session.
final class PayInPaymentFlowTokenStorageClient: Sendable {
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

    func addMethod(
        entryPoint: String,
        paymentMethod: PayabliPayInPaymentFlowMethodInput,
        options: PayabliPayInPaymentFlowTokenStorageOptions = PayabliPayInPaymentFlowTokenStorageOptions()
    ) async throws -> PayabliPayInPaymentFlowStoredPaymentMethod {
        let entry = entryPoint.trimmed
        guard !entry.isEmpty else {
            throw PayabliPayInPaymentFlowTokenStorageError.invalidInput("Entrypoint is required.")
        }
        try paymentMethod.validate(options.validation)

        let request = try addMethodRequest(
            entryPoint: entry,
            paymentMethod: paymentMethod,
            options: options
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
            // The chain refuses an empty credential in the capture surface's error type. Translated,
            // so this surface answers in its own.
            if case PayabliPayInPaymentFlowError.missingAccessToken = error {
                throw PayabliPayInPaymentFlowTokenStorageError.missingAccessToken
            }
            throw error
        }
        diagnostics.logResponse(
            response,
            request: request,
            baseURL: baseURL,
            durationMilliseconds: Date().timeIntervalSince(start) * 1000
        )
        if let failure = decodePaymentMethodFailure(from: response) {
            throw PayabliPayInPaymentFlowTokenStorageError.saveFailed(failure)
        }
        try mapPayabliHTTPError(response: response)
        return try decodeStoredPaymentMethod(from: response)
    }

    /// Builds the request. The transport's chain attaches the credential.
    ///
    /// The idempotency key is set here because the chain runs once per attempt, and a key minted
    /// there would differ on a replay.
    private func addMethodRequest(
        entryPoint: String,
        paymentMethod: PayabliPayInPaymentFlowMethodInput,
        options: PayabliPayInPaymentFlowTokenStorageOptions
    ) throws -> PayabliRequest {
        var headers: [String: String] = [:]
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

    private func decodeStoredPaymentMethod(from response: PayabliResponse) throws -> PayabliPayInPaymentFlowStoredPaymentMethod {
        let decoder = JSONDecoder()
        do {
            let decoded = try decoder.decode(PayabliPayInPaymentFlowTokenStorageAPIResponse.self, from: response.body)
            let approved = decoded.isSuccess == true || decoded.responseData?.resultCode == 1
            guard approved else {
                throw PayabliPayInPaymentFlowTokenStorageError.saveFailed(decoded.failure(httpStatusCode: response.statusCode))
            }
            return PayabliPayInPaymentFlowStoredPaymentMethod(
                storedMethodId: decoded.responseData?.referenceId,
                methodReferenceId: decoded.responseData?.methodReferenceId,
                resultCode: decoded.responseData?.resultCode,
                resultText: decoded.responseData?.resultText,
                customerId: decoded.responseData?.customerId,
                responseText: decoded.responseText,
                apiResponse: decoded
            )
        } catch let error as PayabliPayInPaymentFlowTokenStorageError {
            throw error
        } catch {
            throw PayabliGenericError(
                code: .decodingError,
                reason: "Failed to decode payment method response",
                underlying: error
            )
        }
    }

    private func decodePaymentMethodFailure(from response: PayabliResponse) -> PayabliPayInPaymentFlowSaveFailure? {
        let decoded = try? JSONDecoder().decode(PayabliPayInPaymentFlowTokenStorageAPIResponse.self, from: response.body)
        guard let decoded, decoded.isSuccess == false else { return nil }
        return decoded.failure(httpStatusCode: response.statusCode)
    }
}

private struct TokenStorageAddMethodBody: Encodable {
    let customerData: PayabliPayInPaymentFlowCustomerData?
    let entryPoint: String
    let fallbackAuth: Bool?
    let fallbackAuthAmount: Int?
    let methodDescription: String?
    let paymentMethod: PayabliPayInPaymentFlowMethodInput
    let vendorData: PayabliPayInPaymentFlowVendorData?
    let source: String?
    let subdomain: String?
}

private extension PayabliPayInPaymentFlowTokenStorageOptions {
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

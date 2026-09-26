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
    private let diagnostics: PayabliPayInDiagnostics

    init(
        transport: any PayabliTransport,
        baseURL: URL? = nil,
        diagnostics: PayabliPayInDiagnostics = .disabled
    ) {
        self.transport = transport
        self.baseURL = baseURL
        self.diagnostics = diagnostics
    }

    func addMethod(
        entryPoint: String,
        paymentMethod: PayabliPayInMethodInput,
        options: PayabliPayInTokenStorageOptions = PayabliPayInTokenStorageOptions()
    ) async throws -> PayabliPayInStoredPaymentMethod {
        let entry = entryPoint.trimmed
        guard !entry.isEmpty else {
            throw PayabliPayInTokenStorageError.invalidInput("Entrypoint is required.")
        }
        try paymentMethod.validate(options.validation)
        let storedMethod = paymentMethod.storedMethodType

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
            if case PayabliPayInError.missingAccessToken = error {
                throw PayabliPayInTokenStorageError.missingAccessToken
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
            throw PayabliPayInTokenStorageError.saveFailed(failure)
        }
        try mapPayabliHTTPError(response: response)
        return try decodeStoredPaymentMethod(from: response, method: storedMethod)
    }

    /// Builds the request. The transport's chain attaches the credential.
    ///
    /// No idempotency key: a repeat is not recognisable on this route, so a key sent here is read by
    /// nothing.
    private func addMethodRequest(
        entryPoint: String,
        paymentMethod: PayabliPayInMethodInput,
        options: PayabliPayInTokenStorageOptions
    ) throws -> PayabliRequest {
        return try PayabliRequest.json(
            method: .post,
            path: "/api/TokenStorage/add",
            query: options.queryItems,
            headers: [:],
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

    private func decodeStoredPaymentMethod(
        from response: PayabliResponse,
        method: PayabliPayInStoredMethodType
    ) throws -> PayabliPayInStoredPaymentMethod {
        let decoder = JSONDecoder()
        do {
            let decoded = try decoder.decode(PayabliPayInTokenStorageAPIResponse.self, from: response.body)
            let approved = decoded.isSuccess == true || decoded.responseData?.resultCode == 1
            guard approved else {
                throw PayabliPayInTokenStorageError.saveFailed(decoded.failure(httpStatusCode: response.statusCode))
            }
            return PayabliPayInStoredPaymentMethod(
                storedMethodId: decoded.responseData?.referenceId,
                method: method,
                methodReferenceId: decoded.responseData?.methodReferenceId,
                resultCode: decoded.responseData?.resultCode,
                resultText: decoded.responseData?.resultText,
                customerId: decoded.responseData?.customerId,
                responseText: decoded.responseText,
                apiResponse: decoded
            )
        } catch let error as PayabliPayInTokenStorageError {
            throw error
        } catch {
            throw PayabliGenericError(
                code: .decodingError,
                reason: "Failed to decode payment method response",
                underlying: error
            )
        }
    }

    private func decodePaymentMethodFailure(from response: PayabliResponse) -> PayabliPayInSaveFailure? {
        let decoded = try? JSONDecoder().decode(PayabliPayInTokenStorageAPIResponse.self, from: response.body)
        guard let decoded, decoded.isSuccess == false else { return nil }
        return decoded.failure(httpStatusCode: response.statusCode)
    }
}

private extension PayabliPayInMethodInput {
    /// What this input is charged as once it is stored.
    var storedMethodType: PayabliPayInStoredMethodType {
        switch self {
        case .card: return .card
        case .bankAccount: return .bankAccount
        }
    }
}

private struct TokenStorageAddMethodBody: Encodable {
    let customerData: PayabliPayInCustomerData?
    let entryPoint: String
    let fallbackAuth: Bool?
    let fallbackAuthAmount: Int?
    let methodDescription: String?
    let paymentMethod: PayabliPayInMethodInput
    let vendorData: PayabliPayInVendorData?
    let source: String?
    let subdomain: String?
}

private extension PayabliPayInTokenStorageOptions {
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

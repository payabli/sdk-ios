import Foundation
import PayabliSDKCore

/// HTTP client for `POST /api/TokenStorage/add`.
///
/// It builds the request and reads the response. The credential is attached by the chain inside the
/// transport, so nothing here holds a token or a token source. That transport carries no 401
/// recovery: this surface's credential comes from a per-call provider, not from a session.
final class PayInPaymentFlowTokenStorageClient: Sendable {
    private let transport: any PayabliTransport

    init(transport: any PayabliTransport) {
        self.transport = transport
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

        // The method's own bytes are written from the buffers, spliced in as the body's last member,
        // and overwritten once the transport returns, whatever it returns.
        var body = Data()
        let response: PayabliResponse
        do {
            body = try addMethodBody(entryPoint: entry, paymentMethod: paymentMethod, options: options)
            // No idempotency key: a repeat is not recognisable on this route, so a key sent here is
            // read by nothing. The transport's chain attaches the credential.
            let request = PayabliRequest(
                method: .post,
                path: "/api/TokenStorage/add",
                query: options.queryItems,
                headers: [PayabliRequest.contentTypeHeader: PayabliRequest.applicationJSON],
                body: body
            )
            response = try await transport.perform(request)
        } catch {
            PayInBodyWriter.wipe(&body)
            // The chain refuses an empty credential in the capture surface's error type. Translated,
            // so this surface answers in its own.
            if case PayabliPayInError.missingAccessToken = error {
                throw PayabliPayInTokenStorageError.missingAccessToken
            }
            throw error
        }
        PayInBodyWriter.wipe(&body)
        // The status first: a failed status is the core error for that status, so only a refusal
        // answered on a success status is this surface's own. This route refuses a 400 with prose
        // alone, which is kept as the validation error's detail.
        try mapPayabliHTTPError(response: response) { status in
            status == 400 ? PayabliPaymentError.validation(Self.badRequest(from: response)) : nil
        }
        if let failure = decodePaymentMethodFailure(from: response) {
            throw PayabliPayInTokenStorageError.saveFailed(failure)
        }
        return try decodeStoredPaymentMethod(from: response, method: storedMethod)
    }

    /// The body: everything the options carry, encoded deterministically, with the method's own bytes
    /// spliced in as the last member. The method is written straight out of its buffers, so its digits
    /// never become a `String`.
    ///
    /// - Parameter entryPoint: the paypoint's entry point, already trimmed by the caller.
    /// - Parameter paymentMethod: the card or bank account data the body carries to store.
    /// - Parameter options: what the request carries besides the method, from the customer to the flags.
    /// - Returns: the request body, for the caller to overwrite once the request has been written.
    private func addMethodBody(
        entryPoint: String,
        paymentMethod: PayabliPayInMethodInput,
        options: PayabliPayInTokenStorageOptions
    ) throws -> Data {
        try PayInBodyWriter.splice(
            outer: PayInPaymentFlowJSONBody.encode(TokenStorageAddMethodBody(
                customerData: options.customerData,
                entryPoint: entryPoint,
                fallbackAuth: options.fallbackAuth,
                fallbackAuthAmount: options.fallbackAuthAmount,
                methodDescription: options.methodDescription?.trimmed.nilIfEmpty,
                vendorData: options.vendorData,
                source: options.source?.trimmed.nilIfEmpty,
                subdomain: options.subdomain?.trimmed.nilIfEmpty
            )),
            fragment: try PayInBodyWriter.storeFragment(paymentMethod)
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
                type: .decodingError,
                reason: "Failed to decode payment method response",
                underlying: error
            )
        }
    }

    /// The validation error for a refused request on this route.
    ///
    /// - Parameter response: A 400 from the route.
    /// - Returns: The error carrying the route's `responseText` as its detail, or an empty one when the body has none.
    private static func badRequest(from response: PayabliResponse) -> PayabliValidationError {
        let decoded = try? JSONDecoder().decode(PayabliPayInTokenStorageAPIResponse.self, from: response.body)
        return PayabliValidationError(detail: decoded?.responseText.trimmed.nilIfEmpty)
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

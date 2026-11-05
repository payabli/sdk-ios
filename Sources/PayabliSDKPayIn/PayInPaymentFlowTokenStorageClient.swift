import Foundation
import PayabliSDKCore

/// HTTP client for `POST /api/TokenStorage/add`.
///
/// The credential is attached by the transport's chain, which carries no 401 recovery: this surface's
/// credential comes from a per-call provider.
final class PayInPaymentFlowTokenStorageClient: Sendable {
    private let transport: any PayabliTransport

    init(transport: any PayabliTransport) {
        self.transport = transport
    }

    func addMethod(
        entryPoint: String,
        paymentMethod: PayabliPayInMethodInput,
        options: PayabliPayInStoreOptions = PayabliPayInStoreOptions()
    ) async throws -> PayabliPayInStoredMethod {
        let entry = entryPoint.trimmed
        guard !entry.isEmpty else {
            throw PayabliPayInError.InvalidInput(field: PayInFieldPath.entryPoint, reason: "Entrypoint is required.")
        }
        try paymentMethod.validate(options.validation)
        let storedMethod = paymentMethod.storedMethodType

        var body = Data()
        let response: PayabliResponse
        do {
            body = try addMethodBody(entryPoint: entry, paymentMethod: paymentMethod, options: options)
            // No idempotency key: this route recognises no repeat.
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
            throw error
        }
        PayInBodyWriter.wipe(&body)
        // The status first: a failed status is the core error for that status, except a 400, which this route
        // answers in its own envelope.
        try mapPayabliHTTPError(response: response) { status in
            status == 400 ? Self.badRequest(from: response) : nil
        }
        if let failure = decodePaymentMethodFailure(from: response) {
            throw PayabliPayInError.Refused(failure: failure)
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
        options: PayabliPayInStoreOptions
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
    ) throws -> PayabliPayInStoredMethod {
        let decoder = JSONDecoder()
        do {
            let decoded = try decoder.decode(PayabliPayInTokenStorageAPIResponse.self, from: response.body)
            let approved = decoded.isSuccess == true || decoded.responseData?.resultCode == 1
            guard approved else {
                throw PayabliPayInError.Refused(failure: decoded.failure(httpStatusCode: response.statusCode))
            }
            return PayabliPayInStoredMethod(
                storedMethodId: decoded.responseData?.referenceId,
                method: method,
                methodReferenceId: decoded.responseData?.methodReferenceId,
                customerId: decoded.responseData?.customerId
            )
        } catch let error as PayabliPayInError {
            throw error
        } catch {
            throw PayabliPayInError.Undecodable(
                reason: "Failed to decode payment method response",
                httpStatus: response.statusCode
            )
        }
    }

    /// The error a 400 from this route is: a decline when the payer is blocked by fraud control, otherwise a validation
    /// error.
    ///
    /// - Parameter response: A 400 from the route.
    /// - Returns: ``PayabliPayInError/Refused`` when either code field names 9005; otherwise the validation error carrying
    ///   the status, the code, and `responseText` as its detail when the answer has one.
    private static func badRequest(from response: PayabliResponse) -> any Error {
        let decoded = try? JSONDecoder().decode(PayabliPayInTokenStorageAPIResponse.self, from: response.body)
        let code = serviceCode(of: response)
        if code == blockedByFraudControl || decoded?.responseCode.map(String.init) == blockedByFraudControl {
            let failure = decoded?.failure(httpStatusCode: response.statusCode, code: blockedByFraudControl)
                ?? PayabliPayInFailure(
                    code: blockedByFraudControl,
                    reason: "Unable to save payment method.",
                    httpStatusCode: response.statusCode
                )
            return PayabliPayInError.Refused(failure: failure)
        }
        let validation = PayabliValidationError(detail: decoded?.responseText.trimmed.nilIfEmpty)
        return PayabliPaymentError.validation(validation.carrying(httpStatus: response.statusCode, rawCode: code))
    }

    /// The route's `responseCode` for a payer blocked by fraud control.
    private static let blockedByFraudControl = "9005"

    private func decodePaymentMethodFailure(from response: PayabliResponse) -> PayabliPayInFailure? {
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

private extension PayabliPayInStoreOptions {
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

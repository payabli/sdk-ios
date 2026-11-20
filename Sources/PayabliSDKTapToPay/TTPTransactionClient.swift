import Foundation
import PayabliSDKCore

/// HTTP client for `/api/v2/MoneyIn/initiate` and `/api/v2/MoneyIn/update/{id}`.
///
/// Bearer-auth injection and 401 refresh-and-retry are handled by the
/// `PayabliTransport` passed at init — callers should supply
/// `session.transport` (an `AuthenticatedTransport`).
///
package final class TTPTransactionClient: Sendable {
    private let transport: any PayabliTransport
    private let retryPolicy: RetryPolicy
    private let logger = PayabliLogger(category: .taptopay)

    /// - Parameter transport: the session's authenticated transport.
    /// - Parameter retryPolicy: the policy every close runs under.
    package init(transport: any PayabliTransport, retryPolicy: RetryPolicy = .default) {
        self.transport = transport
        self.retryPolicy = retryPolicy
    }

    /// `POST /api/v2/MoneyIn/initiate`, returning the authoritative `paymentTransId`.
    ///
    /// `paymentMethod.method` is always `"device"`, and the legacy `firstName`, `lastName` and
    /// `customerNumber` are sent as empty strings, not `null`; other nil fields are omitted.
    ///
    /// - Parameter entryPoint: the entry point the transaction is initiated for.
    /// - Parameter deviceId: the device handle the payment method carries.
    /// - Parameter idempotencyKey: the key the service recognises a repeat of this opening by.
    /// - Parameter paymentDetails: the amounts and currency to charge.
    /// - Parameter customer: the customer attached to the transaction, empty for an anonymous payor.
    /// - Parameter invoice: the invoice attached, its number when one is given.
    /// - Parameter orderDescription: an order description, sent as an empty string where none is given.
    /// - Returns: the `paymentTransId` the backend minted.
    package func initiate(
        entryPoint: String,
        deviceId: String,
        idempotencyKey: String,
        paymentDetails: PayabliTTPPaymentDetails,
        customer: PayabliTTPCustomerData = PayabliTTPCustomerData(),
        invoice: PayabliTTPInvoiceData = PayabliTTPInvoiceData(),
        orderDescription: String? = nil
    ) async throws -> String {
        let body = InitiateRequest(
            entryPoint: entryPoint,
            orderDescription: orderDescription ?? "",
            paymentDetails: Self.makeWirePaymentDetails(from: paymentDetails),
            paymentMethod: InitiatePaymentMethod(method: "device", device: deviceId),
            customerData: Self.makeWireCustomer(from: customer),
            invoiceData: invoice.invoiceNumber.map { InitiateInvoiceData(invoiceNumber: $0) }
        )

        // Bearer header is injected by the transport (AuthenticatedTransport).
        let request = try PayabliRequest.json(
            method: .post,
            path: "/api/v2/MoneyIn/initiate",
            headers: [payabliIdempotencyKeyHeader: idempotencyKey],
            jsonBody: body,
            isCallerRefusal: isFraudBlockAnswered401
        )

        // `customerData` is the caller's whole customer record, so the body is
        // reported by size rather than by content. This route carries no assertion
        // headers; the transport's bearer is what authenticates it.
        logger.info("[initiate] → POST \(request.path) bytes=\(request.body?.count ?? 0)")

        let envelope: PayabliV2Envelope<InitiateData>
        let status: Int
        do {
            let response = try await transport.perform(request)
            status = response.statusCode
            if response.statusCode == 409, !Self.isJSONObject(response.body) {
                throw ChargeKeyRefusal()
            }
            // Before the status: the service answers it as a refusal of the request, but it refuses the payer.
            if let code = fraudBlockCode(of: response) {
                throw PayabliTTPError.paymentNotOpened(
                    reason: Self.reason(of: response) ?? code,
                    httpStatus: response.statusCode,
                    rawCode: code
                )
            }
            if response.statusCode == 404 {
                throw PayabliTTPError.cardPresentNotEnabled(httpStatus: response.statusCode, rawCode: serviceCode(of: response))
            }
            if let refusal = CustomerDataRefusal(response: response) {
                throw refusal
            }
            try mapPayabliHTTPError(response: response)
            envelope = try decodePayabliV2Envelope(InitiateData.self, from: response)
        } catch {
            logger.error("[initiate] transport/decode error: \(ErrorSummary.of(error))")
            throw error
        }

        logger
            .info(
                "[initiate] ← isApproved=\(envelope.isApproved) code=\(envelope.code) paymentTransId=\(envelope.data?.paymentTransId ?? "<nil>")"
            )

        guard envelope.isApproved else {
            throw PayabliTTPError.paymentNotOpened(
                reason: envelope.reason ?? envelope.code,
                httpStatus: status,
                rawCode: envelope.code
            )
        }
        // A blank or dot-segment identifier counts as none: the close could not address it, and the card would
        // already be taken.
        guard let data = envelope.data, Self.isAddressable(data.paymentTransId) else {
            let reason = "The opening was approved with no payment"
            throw TapToPayError(type: .decodingError, reason: reason, detail: nil, httpStatus: status, rawCode: envelope.code)
        }
        return data.paymentTransId
    }

    /// Whether `paymentTransId` names a payment the close can address. `.` and `..` pass percent-encoding unchanged
    /// and would name a route instead.
    ///
    /// - Parameter paymentTransId: the payment an approved opening named.
    /// - Returns: `false` when it is blank, `.` or `..` once ``blank`` is trimmed.
    static func isAddressable(_ paymentTransId: String) -> Bool {
        let trimmed = paymentTransId.trimmingCharacters(in: blank)
        return !trimmed.isEmpty && trimmed != "." && trimmed != ".."
    }

    /// Unicode's spaces, separators and the information separators U+001C to U+001F, without U+0085 or U+200B.
    private static let blank = CharacterSet.whitespacesAndNewlines
        .union(CharacterSet(charactersIn: "\u{1C}\u{1D}\u{1E}\u{1F}"))
        .subtracting(CharacterSet(charactersIn: "\u{85}\u{200B}"))

    /// The words a refusal's body gives, when it gives any.
    ///
    /// - Parameter response: the refused answer.
    /// - Returns: the body's `reason`, or nil when it names none or cannot be read.
    private static func reason(of response: PayabliResponse) -> String? {
        (try? JSONDecoder().decode(PayabliV2Envelope<InitiateData>.self, from: response.body))?.reason
    }

    private static func isJSONObject(_ body: Data) -> Bool {
        (try? JSONSerialization.jsonObject(with: body)) is [String: Any]
    }

    private static func makeWirePaymentDetails(
        from details: PayabliTTPPaymentDetails
    ) -> InitiatePaymentDetails {
        InitiatePaymentDetails(
            totalAmount: details.amount,
            serviceFee: details.serviceFee,
            currency: details.currency.asSent.code,
            paymentDescription: details.paymentDescription
        )
    }

    private static func makeWireCustomer(
        from customer: PayabliTTPCustomerData
    ) -> InitiateCustomerData {
        InitiateCustomerData(
            firstName: customer.firstName ?? "",
            lastName: customer.lastName ?? "",
            customerNumber: customer.customerNumber ?? "",
            email: customer.email,
            phone: customer.phone,
            customerId: customer.customerId,
            company: customer.company,
            billingAddress1: customer.billingAddress1,
            billingAddress2: customer.billingAddress2,
            billingCity: customer.billingCity,
            billingState: customer.billingState,
            billingZip: customer.billingZip,
            billingCountry: customer.billingCountry,
            billingPhone: customer.billingPhone,
            billingEmail: customer.billingEmail,
            shippingAddress1: customer.shippingAddress1,
            shippingAddress2: customer.shippingAddress2,
            shippingCity: customer.shippingCity,
            shippingState: customer.shippingState,
            shippingZip: customer.shippingZip,
            shippingCountry: customer.shippingCountry
        )
    }

    /// Closes the transaction with what the reader's processor answered, under the `fiservResponse` key.
    ///
    /// - Parameter paymentTransId: the transaction to close, minted at initiate.
    /// - Parameter result: what the reader read.
    /// - Throws: the last attempt's mapped error; `permissionDenied` at once for a caller that may not act on it.
    func update(paymentTransId: String, result: CardReadResult) async throws {
        let body = UpdateSuccessBody(providerResponse: Self.providerResponse(from: result))
        try await send(paymentTransId: paymentTransId, body: (try? JSONEncoder().encode(body)) ?? Data())
    }

    /// Closes the transaction after a tap that never completed, so an opened transaction is not left standing.
    ///
    /// - Parameter paymentTransId: the transaction to close, minted at initiate.
    /// - Parameter description: why the read failed, sent as a record only.
    /// - Throws: the last attempt's mapped error; `permissionDenied` at once for a caller that may not act on it.
    func updateAfterFailedRead(paymentTransId: String, description: String) async throws {
        let body = UpdateErrorBody(error: .init(
            title: "NFC Tap Failed",
            description: description,
            failureReason: "nfc_read"
        ))
        try await send(paymentTransId: paymentTransId, body: (try? JSONEncoder().encode(body)) ?? Data())
    }

    /// Closes a transaction this SDK holds no reader answer for, with a body that claims no outcome.
    ///
    /// - Parameter paymentTransId: the transaction to close.
    /// - Throws: the last attempt's mapped error; `permissionDenied` at once for a caller that may not act on it.
    func close(paymentTransId: String) async throws {
        try await send(paymentTransId: paymentTransId, body: Data("{}".utf8))
    }

    /// The closes' shared `PATCH /api/v2/MoneyIn/update/{paymentTransId}`, retried. Any 2xx is success and the
    /// response is not decoded.
    ///
    /// - Parameter paymentTransId: the transaction the close is sent for.
    /// - Parameter body: the encoded close.
    /// - Throws: the last attempt's mapped error; `permissionDenied` at once, unretried, for a caller the route says
    ///   may not act on the payment.
    private func send(paymentTransId: String, body: Data) async throws {
        let logger = self.logger
        let path = "/api/v2/MoneyIn/update/\(PercentEncoding.segment(paymentTransId))"
        let transport = self.transport

        try await Retry.run(policy: retryPolicy, logger: logger) { attempt in
            let request = PayabliRequest(
                method: .patch,
                path: path,
                headers: ["Content-Type": "application/json"],
                body: body
            )
            // The success body carries the provider's whole response, and with
            // it `paymentTokens.tokenData` and the card's expiry. Size only.
            logger.info("[update/\(attempt)] → PATCH \(path) bytes=\(body.count)")
            let response = try await transport.perform(request)
            logger.info("[update/\(attempt)] ← [\(response.statusCode)] bytes=\(response.body.count)")
            if let refusal = Self.notPermitted(response) {
                throw refusal
            }
            try mapPayabliHTTPError(response: response)
        }
    }

    /// The refusal of a caller that may not act on the payment's paypoint, which the update route answers 400 with
    /// code `E9001`.
    ///
    /// - Parameter response: the update's answer.
    /// - Returns: `permissionDenied` carrying the status and code, or nil for any other answer.
    static func notPermitted(_ response: PayabliResponse) -> PayabliGenericError? {
        guard response.statusCode == 400, serviceCode(of: response) == "E9001" else { return nil }
        return PayabliGenericError(
            type: .permissionDenied,
            reason: PayabliErrorType.permissionDenied.message,
            httpStatus: response.statusCode,
            rawCode: "E9001"
        )
    }

    /// Prefer the provider's own response JSON when it's available (atomic
    /// flow). Fall back to the payload-only shape otherwise, so the backend
    /// always sees the same wire envelope regardless of provider.
    ///
    /// - Parameter result: what the reader read, whose provider response is encoded.
    /// - Returns: the provider's response JSON where it carries one, otherwise the payload-only shape.
    private static func providerResponse(from result: CardReadResult) -> ProviderResponsePayload {
        if let json = result.providerResponseJSON {
            return .opaqueJSON(json)
        }
        return .payloadOnly(PayloadOnlyProviderResponse(
            provider: result.provider,
            encryptedPayload: result.encryptedPayload.base64EncodedString(),
            cardNetwork: result.cardNetwork,
            providerMetadata: result.providerMetadata
        ))
    }
}

/// A 409 whose body is not a JSON object, which only the check refusing a key it has already seen sends. Any other 409,
/// such as a refused duplicate sale, carries a JSON body.
struct ChargeKeyRefusal: PayabliError {
    var type: PayabliErrorType {
        .conflict
    }

    var httpStatus: Int? {
        409
    }

    var reason: String {
        PayabliErrorType.conflict.message
    }

    var detail: String? {
        nil
    }
}

/// A 400 with code `E7020` blaming `customerData`: the customer the charge sent was refused before any card was read.
/// It reads as the validation error it is wherever it is not translated for a host.
struct CustomerDataRefusal: PayabliError {
    let validation: PayabliValidationError
    let requiredFields: [String]

    /// The refusal a response carries, or nil for any other response.
    ///
    /// - Parameter response: the opening's response.
    /// - Returns: the refusal, with the fields its text names, or nil when the response is not this refusal.
    init?(response: PayabliResponse) {
        guard response.statusCode == 400,
              let validation = try? JSONDecoder().decode(PayabliValidationError.self, from: response.body),
              validation.rawCode == "E7020",
              let entries = validation.errors["customerData"]
        else { return nil }
        self.validation = validation.carrying(httpStatus: response.statusCode, rawCode: validation.rawCode)
        requiredFields = entries.lazy.compactMap { Self.fieldsNamed(in: $0.message) }.first ?? []
    }

    var type: PayabliErrorType {
        validation.type
    }

    var reason: String {
        validation.reason
    }

    var detail: String? {
        validation.detail
    }

    var httpStatus: Int? {
        validation.httpStatus
    }

    var rawCode: String? {
        validation.rawCode
    }

    var errorDescription: String? {
        validation.errorDescription
    }

    private static let identifiersPrefix = "Missing customer identifiers: "

    /// The ``PayabliTTPCustomerData`` property that sets each identifier key, by the key lowercased.
    private static let propertyForKey: [String: String] = [
        "customernumber": "customerNumber",
        "firstname": "firstName",
        "lastname": "lastName",
        "company": "company",
        "phone": "billingPhone",
        "email": "billingEmail",
        "city": "billingCity",
        "state": "billingState",
        "zip": "billingZip",
        "country": "billingCountry",
        "shippingcity": "shippingCity",
        "shippingstate": "shippingState",
        "shippingzip": "shippingZip",
        "shippingcountry": "shippingCountry"
    ]

    /// The field names a refusal's text lists after its fixed prefix, or nil for text that lists none.
    ///
    /// - Parameter message: the refusal's text for the customer.
    /// - Returns: the names in the order given, each as the customer property that sets it, or as given when no
    ///   property does.
    private static func fieldsNamed(in message: String) -> [String]? {
        guard message.hasPrefix(identifiersPrefix) else { return nil }
        return message.dropFirst(identifiersPrefix.count)
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
            .map { propertyForKey[$0.lowercased()] ?? $0 }
    }
}

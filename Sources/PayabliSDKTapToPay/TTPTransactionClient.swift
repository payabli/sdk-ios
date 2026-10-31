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
    private let logger = PayabliLogger(category: .taptopay)

    package init(transport: any PayabliTransport) {
        self.transport = transport
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
            jsonBody: body
        )

        // `customerData` is the caller's whole customer record, so the body is
        // reported by size rather than by content. This route carries no assertion
        // headers; the transport's bearer is what authenticates it.
        logger.info("[initiate] → POST \(request.path) bytes=\(request.body?.count ?? 0)")

        let envelope: PayabliV2Envelope<InitiateData>
        do {
            let response = try await transport.perform(request)
            if response.statusCode == 409, !Self.isJSONObject(response.body) {
                throw ChargeKeyRefusal()
            }
            if response.statusCode == 404 {
                throw PayabliTTPError.cardPresentNotEnabled
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
            throw PayabliTTPError.paymentNotOpened(reason: envelope.reason ?? envelope.code)
        }
        // A blank or dot-segment identifier counts as none: the close could not address it, and the card would
        // already be taken.
        guard let data = envelope.data, Self.isAddressable(data.paymentTransId) else {
            throw TapToPayError(type: .decodingError, reason: "The opening was approved with no payment", detail: nil)
        }
        return data.paymentTransId
    }

    /// Whether `paymentTransId` names a payment the close can address. `.` and `..` pass percent-encoding unchanged
    /// and would name a route instead.
    ///
    /// - Parameter paymentTransId: the payment an approved opening named.
    /// - Returns: `false` when it is blank, `.` or `..` once trimmed.
    private static func isAddressable(_ paymentTransId: String) -> Bool {
        let trimmed = paymentTransId.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed != "." && trimmed != ".."
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
            currency: details.currency,
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

    /// Encodes a typed update payload for `PATCH /MoneyIn/update/{id}`.
    ///
    /// Atomic providers forward their full response; payload-only providers are wrapped into the same
    /// shape.
    ///
    /// - Parameter payload: what the reader did, as the success or failure to encode.
    /// - Returns: the wire body for the update: the response under the `fiservResponse` key on a success, an `error` object on a failure.
    static func updateBody(for payload: TTPUpdatePayload) -> Data {
        let encoder = JSONEncoder()
        switch payload {
        case let .success(result):
            let body = UpdateSuccessBody(providerResponse: providerResponse(from: result))
            return (try? encoder.encode(body)) ?? Data()

        case let .nfcFailure(description):
            let body = UpdateErrorBody(error: .init(
                title: "NFC Tap Failed",
                description: description,
                failureReason: "nfc_read"
            ))
            return (try? encoder.encode(body)) ?? Data()
        }
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
              let entries = validation.errors?["customerData"]
        else { return nil }
        self.validation = validation
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

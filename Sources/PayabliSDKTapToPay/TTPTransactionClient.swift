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

        guard envelope.isApproved, let data = envelope.data else {
            throw PayabliTTPError.initiateFailed(reason: envelope.reason ?? envelope.code)
        }
        return data.paymentTransId
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

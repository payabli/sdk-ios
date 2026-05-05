import Foundation
import PayabliSDKCore

/// HTTP client for `/api/v2/MoneyIn/initiate` and `/api/v2/MoneyIn/update/{id}`.
///
/// Every request uses the same access token held by `PayabliAuth`; the v2
/// envelope's chained `token` field is intentionally ignored.
///
public final class TTPTransactionClient: Sendable {
    private let service: PayabliService
    private let auth: PayabliAuth
    private let logger = PayabliLogger(category: .taptopay)

    public init(service: PayabliService, auth: PayabliAuth) {
        self.service = service
        self.auth = auth
    }

    /// `POST /api/v2/MoneyIn/initiate` — returns the authoritative
    /// `paymentTransId` from the backend. Mirrors the reference flow used by
    /// the Fiserv direct POC (`SaleView.swift`): `paymentMethod.method` is
    /// always `"device"` (the POI-device flavor), and the three legacy fields
    /// (`firstName`, `lastName`, `customerNumber`) are sent as empty strings
    /// rather than `null` for backward compatibility. All other customer
    /// fields are omitted from the JSON when nil.
    public func initiate(
        entryPoint: String,
        deviceId: String,
        paymentDetails: PayabliTTPPaymentDetails,
        customer: PayabliTTPCustomerData = PayabliTTPCustomerData(),
        invoice: PayabliTTPInvoiceData = PayabliTTPInvoiceData(),
        orderDescription: String? = nil
    ) async throws -> String {
        let token = await auth.currentAccessToken()

        let body = InitiateRequest(
            entryPoint: entryPoint,
            orderDescription: orderDescription ?? "",
            paymentDetails: Self.makeWirePaymentDetails(from: paymentDetails),
            paymentMethod: InitiatePaymentMethod(method: "device", device: deviceId),
            customerData: Self.makeWireCustomer(from: customer),
            invoiceData: invoice.invoiceNumber.map { InitiateInvoiceData(invoiceNumber: $0) }
        )

        let request = try PayabliRequest.json(
            method: .post,
            path: "/api/v2/MoneyIn/initiate",
            headers: ["Authorization": "Bearer \(token)"],
            jsonBody: body
        )

        let headersDump = request.headers
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: " | ")
        let bodyDump = request.body.flatMap { String(data: $0, encoding: .utf8) } ?? "<nil>"
        logger.info("[initiate] → POST \(request.path)")
        logger.info("[initiate] headers: \(headersDump)")
        // Body carries PII (billing/shipping/email/phone) — keep redacted in
        // shared OS logs.
        logger.info("[initiate] body", private: bodyDump)

        let envelope: PayabliV2Envelope<InitiateData>
        do {
            envelope = try await service.performV2(request, decoding: InitiateData.self)
        } catch {
            logger.error("[initiate] transport/decode error: \(String(describing: error))")
            throw error
        }

        logger.info("[initiate] ← isApproved=\(envelope.isApproved) code=\(envelope.code) paymentTransId=\(envelope.data?.paymentTransId ?? "<nil>")")

        guard envelope.isApproved, let data = envelope.data else {
            throw PayabliTTPError.initiateFailed(reason: envelope.reason ?? envelope.code)
        }
        return data.paymentTransId
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
    /// Atomic providers forward their full response under the
    /// `providerResponse` Swift field (mapped to the legacy `fiservResponse`
    /// JSON key on the wire); payload-only providers are wrapped into the
    /// same shape.
    static func updateBody(for payload: TTPUpdatePayload) -> Data {
        let encoder = JSONEncoder()
        switch payload {
        case .success(let result):
            let body = UpdateSuccessBody(providerResponse: providerResponse(from: result))
            return (try? encoder.encode(body)) ?? Data()

        case .nfcFailure(let description):
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

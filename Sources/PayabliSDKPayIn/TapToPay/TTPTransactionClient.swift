import Foundation
import PayabliSDKCore

// MARK: - Request shapes (PRD §8.2 "Initiate request", "Update request")

struct InitiatePaymentDetails: Encodable {
    let totalAmount: Decimal
    let serviceFee: Decimal
}

struct InitiateCustomerData: Encodable {
    let firstName: String
    let lastName: String
    let customerNumber: String
}

struct InitiatePaymentMethod: Encodable {
    let method: String           // "cloud" (POI-device-backed TTP flow)
    let device: String           // Payabli deviceId (from /attest or /activate)
}

struct InitiateRequest: Encodable {
    let entryPoint: String
    let orderId: String
    let orderDescription: String
    let paymentDetails: InitiatePaymentDetails
    let paymentMethod: InitiatePaymentMethod
    let customerData: InitiateCustomerData
}

struct InitiateData: Decodable, Sendable {
    let paymentTransId: String
}

/// Success update body — forwards the full provider response opaquely
/// (PRD §8.2 "Update request (success)").
struct UpdateSuccessBody: Encodable {
    let fiservResponse: AnyEncodable
}

/// Error update body — NFC failure notification.
struct UpdateErrorBody: Encodable {
    struct ErrorDetail: Encodable {
        let title: String
        let description: String
        let failureReason: String
    }
    let error: ErrorDetail
}

/// Type-erased Encodable so a generic provider payload can be serialized without
/// forcing the call site to know its concrete type.
struct AnyEncodable: Encodable {
    private let encode: (Encoder) throws -> Void
    init<T: Encodable>(_ value: T) {
        encode = { try value.encode(to: $0) }
    }
    init(_ dict: [String: Any]) {
        encode = { encoder in
            let data = try JSONSerialization.data(withJSONObject: dict)
            let json = try JSONDecoder().decode(JSONValue.self, from: data)
            try json.encode(to: encoder)
        }
    }
    func encode(to encoder: Encoder) throws {
        try encode(encoder)
    }
}

/// Minimal internal JSONValue for round-tripping arbitrary provider payloads.
private enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null; return }
        if let v = try? c.decode(Bool.self) { self = .bool(v); return }
        if let v = try? c.decode(Double.self) { self = .number(v); return }
        if let v = try? c.decode(String.self) { self = .string(v); return }
        if let v = try? c.decode([JSONValue].self) { self = .array(v); return }
        if let v = try? c.decode([String: JSONValue].self) { self = .object(v); return }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "Unknown JSON value"
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
}

// MARK: - Client

/// HTTP client for `/api/v2/MoneyIn/initiate` and `/api/v2/MoneyIn/update/{id}`.
///
/// Every request uses the same access token held by `PayabliAuth`; the v2
/// envelope's chained `token` field is intentionally ignored.
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
    /// always `"cloud"` (the POI-device flavor that the backend looks for in
    /// `MoneyInAuth.cs` — `method == "cloud"`), and empty fields are sent as
    /// strings rather than `null`.
    ///
    /// Customer and order data flow in as structured values so the call site
    /// (`PayabliTTP.charge`) can thread the same snapshot through every stage
    /// of the charge pipeline (initiate → card reader → update).
    public func initiate(
        entryPoint: String,
        amount: Decimal,
        serviceFee: Decimal = 0,
        deviceId: String,
        customer: PayabliTTPCustomerData = PayabliTTPCustomerData(),
        order: PayabliTTPOrderData = PayabliTTPOrderData()
    ) async throws -> String {
        let token = await auth.currentAccessToken()
        let body = InitiateRequest(
            entryPoint: entryPoint,
            orderId: order.orderId ?? "",
            orderDescription: order.orderDescription ?? "",
            paymentDetails: InitiatePaymentDetails(totalAmount: amount, serviceFee: serviceFee),
            paymentMethod: InitiatePaymentMethod(method: "device", device: deviceId),
            customerData: InitiateCustomerData(
                firstName: customer.firstName ?? "",
                lastName: customer.lastName ?? "",
                customerNumber: customer.customerNumber ?? ""
            )
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
        logger.info("[initiate] body: \(bodyDump)")

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

    /// Success-update body encoder. Producer-agnostic: the provider JSON is
    /// passed as a dictionary and forwarded under `fiservResponse`.
    public static func successUpdateBody(providerResponse: [String: Any]) -> Data {
        let body = UpdateSuccessBody(fiservResponse: AnyEncodable(providerResponse))
        return (try? JSONEncoder().encode(body)) ?? Data()
    }

    /// Error-update body encoder (PRD §8.2 "Update request (NFC failure notification)").
    public static func errorUpdateBody(
        title: String = "NFC Tap Failed",
        description: String,
        failureReason: String = "nfc_read"
    ) -> Data {
        let body = UpdateErrorBody(error: .init(
            title: title,
            description: description,
            failureReason: failureReason
        ))
        return (try? JSONEncoder().encode(body)) ?? Data()
    }
}

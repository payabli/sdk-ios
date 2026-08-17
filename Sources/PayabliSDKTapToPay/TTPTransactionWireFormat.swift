import Foundation

// MARK: - Initiate request (PRD §8.2 "Initiate request")

struct InitiatePaymentDetails: Encodable {
    let totalAmount: Decimal
    let serviceFee: Decimal
    let currency: String?
    let paymentDescription: String?

    enum CodingKeys: String, CodingKey {
        case totalAmount, serviceFee, currency, paymentDescription
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(totalAmount, forKey: .totalAmount)
        try c.encode(serviceFee, forKey: .serviceFee)
        try c.encodeIfPresent(currency, forKey: .currency)
        try c.encodeIfPresent(paymentDescription, forKey: .paymentDescription)
    }
}

struct InitiateCustomerData: Encodable {
    // Existing — empty string when source is nil (preserves current behavior).
    let firstName: String
    let lastName: String
    let customerNumber: String

    // Existing fields, newly serialized — omitted when nil.
    let email: String?
    let phone: String?

    // New — omitted when nil.
    let customerId: Int?
    let company: String?

    let billingAddress1: String?
    let billingAddress2: String?
    let billingCity: String?
    let billingState: String?
    let billingZip: String?
    let billingCountry: String?
    let billingPhone: String?
    let billingEmail: String?

    let shippingAddress1: String?
    let shippingAddress2: String?
    let shippingCity: String?
    let shippingState: String?
    let shippingZip: String?
    let shippingCountry: String?

    enum CodingKeys: String, CodingKey {
        case firstName, lastName, customerNumber, email, phone
        case customerId, company
        case billingAddress1, billingAddress2, billingCity, billingState
        case billingZip, billingCountry, billingPhone, billingEmail
        case shippingAddress1, shippingAddress2, shippingCity, shippingState
        case shippingZip, shippingCountry
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(firstName, forKey: .firstName)
        try c.encode(lastName, forKey: .lastName)
        try c.encode(customerNumber, forKey: .customerNumber)
        try c.encodeIfPresent(email, forKey: .email)
        try c.encodeIfPresent(phone, forKey: .phone)
        try c.encodeIfPresent(customerId, forKey: .customerId)
        try c.encodeIfPresent(company, forKey: .company)
        try c.encodeIfPresent(billingAddress1, forKey: .billingAddress1)
        try c.encodeIfPresent(billingAddress2, forKey: .billingAddress2)
        try c.encodeIfPresent(billingCity, forKey: .billingCity)
        try c.encodeIfPresent(billingState, forKey: .billingState)
        try c.encodeIfPresent(billingZip, forKey: .billingZip)
        try c.encodeIfPresent(billingCountry, forKey: .billingCountry)
        try c.encodeIfPresent(billingPhone, forKey: .billingPhone)
        try c.encodeIfPresent(billingEmail, forKey: .billingEmail)
        try c.encodeIfPresent(shippingAddress1, forKey: .shippingAddress1)
        try c.encodeIfPresent(shippingAddress2, forKey: .shippingAddress2)
        try c.encodeIfPresent(shippingCity, forKey: .shippingCity)
        try c.encodeIfPresent(shippingState, forKey: .shippingState)
        try c.encodeIfPresent(shippingZip, forKey: .shippingZip)
        try c.encodeIfPresent(shippingCountry, forKey: .shippingCountry)
    }
}

struct InitiatePaymentMethod: Encodable {
    let method: String // "device" (POI-device-backed TTP flow)
    let device: String // Payabli deviceId (from /attest or /activate)
}

struct InitiateInvoiceData: Encodable {
    let invoiceNumber: String
}

struct InitiateRequest: Encodable {
    let entryPoint: String
    let orderDescription: String
    let paymentDetails: InitiatePaymentDetails
    let paymentMethod: InitiatePaymentMethod
    let customerData: InitiateCustomerData
    let invoiceData: InitiateInvoiceData?

    enum CodingKeys: String, CodingKey {
        case entryPoint, orderDescription, paymentDetails, paymentMethod
        case customerData, invoiceData
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(entryPoint, forKey: .entryPoint)
        try c.encode(orderDescription, forKey: .orderDescription)
        try c.encode(paymentDetails, forKey: .paymentDetails)
        try c.encode(paymentMethod, forKey: .paymentMethod)
        try c.encode(customerData, forKey: .customerData)
        try c.encodeIfPresent(invoiceData, forKey: .invoiceData)
    }
}

struct InitiateData: Decodable, Sendable {
    let paymentTransId: String
}

// MARK: - Update request (PRD §8.2 "Update request (success/NFC failure)")

/// Typed payload for `PATCH /api/v2/MoneyIn/update/{paymentTransId}`.
/// Keeps the two shapes the backend accepts (success vs NFC failure) in one
/// semantic type so the facade never handles raw `Data` bodies.
enum TTPUpdatePayload {
    case success(CardReadResult)
    case nfcFailure(description: String)
}

/// Success update body — forwards the processor response to the backend.
///
/// The Swift field is named `providerResponse` for provider-agnostic clarity,
/// but the wire JSON key is still `fiservResponse` because the backend
/// contract has not been renamed yet. The `CodingKeys` mapping below
/// preserves the wire format verbatim — do not change it without a
/// coordinated backend rollout.
struct UpdateSuccessBody: Encodable {
    let providerResponse: ProviderResponsePayload

    enum CodingKeys: String, CodingKey {
        case providerResponse = "fiservResponse"
    }
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

// MARK: - Provider response (serialized under the `fiservResponse` wire key)

/// What the SDK forwards under the `providerResponse` Swift field — which
/// still serializes to the `fiservResponse` JSON key on the wire (see
/// `UpdateSuccessBody.CodingKeys`). Two flavors the backend accepts
/// interchangeably:
///
/// - `.opaqueJSON`: the adapter hit the processor itself (atomic flow, e.g.
///   Fiserv) and owns the raw response JSON. Forwarded verbatim.
/// - `.payloadOnly`: the adapter captured an encrypted blob + metadata; the
///   backend decrypts and charges.
enum ProviderResponsePayload: Encodable {
    case opaqueJSON(Data)
    case payloadOnly(PayloadOnlyProviderResponse)

    func encode(to encoder: Encoder) throws {
        switch self {
        case let .opaqueJSON(json):
            // Re-parse the provider's JSON bytes into a `JSONValue` tree so it
            // merges cleanly into the outer encoder (same output as writing
            // the bytes directly, but type-safe).
            let value = try JSONDecoder().decode(JSONValue.self, from: json)
            try value.encode(to: encoder)
        case let .payloadOnly(payload):
            try payload.encode(to: encoder)
        }
    }
}

/// Structured shape sent by payload-only adapters.
struct PayloadOnlyProviderResponse: Encodable {
    let provider: String
    let encryptedPayload: String // base64
    let cardNetwork: String?
    let providerMetadata: [String: String]
}

// MARK: - Private helpers

/// Minimal internal JSONValue for round-tripping opaque provider payloads.
private enum JSONValue: Codable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case null
    case array([JSONValue])
    case object([String: JSONValue])

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() {
            self = .null
            return
        }
        if let v = try? c.decode(Bool.self) {
            self = .bool(v)
            return
        }
        if let v = try? c.decode(Double.self) {
            self = .number(v)
            return
        }
        if let v = try? c.decode(String.self) {
            self = .string(v)
            return
        }
        if let v = try? c.decode([JSONValue].self) {
            self = .array(v)
            return
        }
        if let v = try? c.decode([String: JSONValue].self) {
            self = .object(v)
            return
        }
        throw DecodingError.dataCorruptedError(
            in: c, debugDescription: "Unknown JSON value"
        )
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case let .bool(v): try c.encode(v)
        case let .number(v): try c.encode(v)
        case let .string(v): try c.encode(v)
        case let .array(v): try c.encode(v)
        case let .object(v): try c.encode(v)
        }
    }
}

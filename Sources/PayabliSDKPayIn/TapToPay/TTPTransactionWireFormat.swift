import Foundation

// MARK: - Initiate request (PRD §8.2 "Initiate request")

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

// MARK: - Update request (PRD §8.2 "Update request (success/NFC failure)")

/// Typed payload for `PATCH /api/v2/MoneyIn/update/{paymentTransId}`.
/// Keeps the two shapes the backend accepts (success vs NFC failure) in one
/// semantic type so the facade never handles raw `Data` bodies.
enum TTPUpdatePayload {
    case success(CardReadResult)
    case nfcFailure(description: String)
}

/// Success update body — forwards the provider response under `fiservResponse`.
struct UpdateSuccessBody: Encodable {
    let fiservResponse: ProviderResponsePayload
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

// MARK: - Provider response (under `fiservResponse`)

/// What the SDK forwards under the `fiservResponse` key on a successful
/// `/update`. Two flavors the backend accepts interchangeably:
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
        case .opaqueJSON(let json):
            // Re-parse the provider's JSON bytes into a `JSONValue` tree so it
            // merges cleanly into the outer encoder (same output as writing
            // the bytes directly, but type-safe).
            let value = try JSONDecoder().decode(JSONValue.self, from: json)
            try value.encode(to: encoder)
        case .payloadOnly(let payload):
            try payload.encode(to: encoder)
        }
    }
}

/// Structured shape sent by payload-only adapters.
struct PayloadOnlyProviderResponse: Encodable {
    let provider: String
    let encryptedPayload: String        // base64
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

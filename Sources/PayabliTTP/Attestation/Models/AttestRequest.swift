import Foundation

/// Body for POST /api/v2/device/taptopay/attest
struct AttestRequest: Encodable {
    let challengeId: String
    let keyId: String
    let attestation: String
    let deviceId: String
}

/// Decoded `responseData` from POST /api/v2/device/taptopay/attest
struct AttestResponse: Decodable {
    let registered: Bool
    let isSandbox: Bool
}

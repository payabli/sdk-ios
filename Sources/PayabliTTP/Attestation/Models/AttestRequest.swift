import Foundation

/// Body for POST /api/v2/TapToPay/attest
struct AttestRequest: Encodable {
    let keyId: String
    let attestation: String
    let deviceId: String
}

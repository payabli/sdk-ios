import Foundation

/// Decoded `responseData` from POST /api/v2/device/taptopay/challenge.
struct ChallengeResponse: Decodable {
    /// Opaque ID used by the backend to look up this nonce on POST /attest.
    let challengeId: String
    /// Base64-encoded random nonce passed to `DCAppAttestService.attestKey()` as `SHA256(challenge)`.
    let challenge: String
}

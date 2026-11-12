import Foundation

// MARK: - Backend wire types

//
// Endpoint-specific DTOs for the attestation family. Generic envelope
// scaffolding lives in `PayabliSDKCore.PayabliEnvelope`.

// MARK: /challenge

struct ChallengeRequest: Encodable { let entry: String }

struct ChallengeResponse: Decodable {
    let challengeId: String
    /// The challenge's bytes, read from base64. A value that is not base64 fails the decode.
    let challenge: Data

    private enum CodingKeys: String, CodingKey {
        case challengeId
        case challenge
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        challengeId = try container.decode(String.self, forKey: .challengeId)
        let text = try container.decode(String.self, forKey: .challenge)
        guard let bytes = Data(base64Encoded: text) else {
            throw DecodingError.dataCorruptedError(forKey: .challenge, in: container, debugDescription: "not base64")
        }
        challenge = bytes
    }
}

// MARK: /register

struct RegisterRequest: Encodable {
    let entry: String
    let keyId: AppAttestKeyId
    let hardwareId: String
    let model: String
    let osVersion: String
    let platform: String
}

struct RegisterResponse: Decodable {
    let deviceId: String
    let status: String?
}

// MARK: /attest

struct AttestRequest: Encodable {
    let challengeId: String
    let keyId: AppAttestKeyId
    let attestation: AttestationObject
    let deviceId: String
    let appId: String
    let entry: String
    let platform: String
}

// MARK: /activate

struct ActivateRequest: Encodable {
    let entry: String
    let deviceId: String
    let activationCode: String
}

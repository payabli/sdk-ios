import Foundation

// MARK: - Backend wire types (PRD §8.2)

//
// Endpoint-specific DTOs for the attestation family. Generic envelope
// scaffolding lives in `PayabliSDKCore.PayabliEnvelope`.

// MARK: /challenge

struct ChallengeRequest: Encodable { let entry: String }

struct ChallengeResponse: Decodable {
    let challengeId: String
    let challenge: String
}

// MARK: /register

struct RegisterRequest: Encodable {
    let entry: String
    let keyId: AppAttestKeyId
    let hardwareId: String
    let deviceName: String
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

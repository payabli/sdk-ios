import Foundation

// MARK: - Backend wire types (PRD §8.2)
//
// Split from `AppAttestService.swift` for readability. Same module — internal access.

// MARK: /challenge

struct ChallengeRequest: Encodable { let entry: String }

struct ChallengeResponse: Decodable {
    let challengeId: String
    let challenge: String
}

// MARK: /register

struct RegisterRequest: Encodable {
    let entry: String
    let keyId: String
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
    let keyId: String
    let attestation: String
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

struct ActivationChallengeRequest: Encodable {
    let entry: String
    let deviceId: String
}

struct ActivationChallengePayload: Decodable {
    let code: String
    let expiresAt: Date?
    let alreadyIssued: Bool?
}

struct ActivationChallengeEnvelope: Decodable {
    let responseData: ActivationChallengePayload?
}

// MARK: Generic envelope helpers (HTTP 200 + isSuccess: false)

struct DeclinePayload: Decodable {
    let resultCode: Int?
    let resultText: String?
}

struct RawEnvelope: Decodable {
    let isSuccess: Bool?
    let responseText: String?
}

struct SuccessEnvelope<Payload: Decodable>: Decodable {
    let responseData: Payload?
}

struct DeclineEnvelope: Decodable {
    let responseData: DeclinePayload?
}

struct EmptyPayload: Decodable {}

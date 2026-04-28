import Foundation
import CryptoKit
import PayabliSDKCore

// MARK: - Attestation flow (PRD §18.1) & per-request assertions (PRD §18.2)

extension AppAttestService {

    public func attest(entry: String, appId: String) async throws -> AttestationResult {
        guard attestor.isSupported else {
            throw PayabliTTPError.attestationFailed(reason: "App Attest not supported on this device")
        }

        // 1. POST /challenge
        let challenge = try await postChallenge(entry: entry)

        // 2. Resolve hw identifiers + existing or freshly generated keyId
        let registerReq = RegisterRequest(
            entry: entry,
            keyId: try await resolveOrCreateKeyId(),
            hardwareId: hardwareIdProvider(),
            deviceName: deviceNameProvider(),
            model: modelProvider(),
            osVersion: osVersionProvider(),
            platform: Self.platform
        )

        // 3. POST /register
        let register = try await postRegister(registerReq)
        let isPending = register.status?.lowercased() == "pending"
        if isPending {
            logger.info("Device registered in pending state — completing attestation before prompting for activation code")
        }

        // Persist deviceId BEFORE signalling pending: `/activate` requires an
        // assertion whose headers come from keychain, and the server expects
        // `deviceId` in the `/activate` body.
        try storage.set(register.deviceId, forKey: PayabliKeychainKey.deviceId)

        // 4+5. Attest key with SHA256(challenge)
        guard let challengeData = Data(base64Encoded: challenge.challenge) ?? challenge.challenge.data(using: .utf8) else {
            throw PayabliTTPError.attestationFailed(reason: "Could not decode challenge")
        }
        let clientDataHash = ClientDataHash(Data(SHA256.hash(data: challengeData)))
        let attestation = try await attestor.attestKey(registerReq.keyId, clientDataHash: clientDataHash)

        // 6. POST /attest — required for both Active and Pending devices; it
        //    creates the `DeviceAttestations` row that `/activate` verifies.
        try await postAttest(AttestRequest(
            challengeId: challenge.challengeId,
            keyId: registerReq.keyId,
            attestation: attestation,
            deviceId: register.deviceId,
            appId: appId,
            entry: entry,
            platform: Self.platform
        ))

        if isPending {
            logger.info("Attestation stored — device still pending activation")
            throw PayabliTTPError.devicePendingActivation
        }

        logger.info("Attestation completed")
        return AttestationResult(keyId: registerReq.keyId.rawValue, deviceId: register.deviceId)
    }

    public func generateAssertion() async throws -> AssertionHeaders {
        guard let storedKeyId = storage.string(forKey: PayabliKeychainKey.keyId),
              let deviceId = storage.string(forKey: PayabliKeychainKey.deviceId) else {
            throw PayabliTTPError.attestationFailed(reason: "Missing attestation state")
        }
        let keyId = AppAttestKeyId(storedKeyId)

        // The server verifies the assertion against `X-Assertion-Timestamp`, so
        // client-data is the SHA-256 of the same ISO-8601 string we send.
        let timestamp = Self.iso8601WithFractional.string(from: Date())
        let clientDataHash = ClientDataHash(Data(SHA256.hash(data: Data(timestamp.utf8))))
        let assertion = try await attestor.generateAssertion(keyId, clientDataHash: clientDataHash)

        return AssertionHeaders(
            assertion: assertion.base64,
            keyId: keyId.rawValue,
            deviceId: deviceId,
            timestamp: timestamp
        )
    }

    // MARK: - Attest helpers

    static let platform = "Ios"

    static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private func resolveOrCreateKeyId() async throws -> AppAttestKeyId {
        if let existing = storage.string(forKey: PayabliKeychainKey.keyId) {
            return AppAttestKeyId(existing)
        }
        let keyId = try await attestor.generateKey()
        try storage.set(keyId.rawValue, forKey: PayabliKeychainKey.keyId)
        return keyId
    }
}

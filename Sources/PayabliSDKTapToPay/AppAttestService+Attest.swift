import Foundation
import CryptoKit
import PayabliSDKCore

// MARK: - Attestation flow (PRD §18.1) & per-request assertions (PRD §18.2)

extension AppAttestService {

    /// Apple's DeviceCheck / App Attest error domain (`DCError`). Bridged as a
    /// string so this file needs no `import DeviceCheck` and stays testable on
    /// hosts where `DCAppAttestService` is unavailable.
    static let deviceCheckErrorDomain = "com.apple.devicecheck.error"

    public func attest(entry: String, appId: String) async throws -> AttestationResult {
        guard attestor.isSupported else {
            throw PayabliTTPError.attestationFailed(reason: "App Attest not supported on this device")
        }

        // 1. POST /challenge
        let challenge = try await postChallenge(entry: entry)

        // 2. Generate a fresh App Attest key for this attempt.
        //
        //    The keyId is deliberately NOT persisted here. Persisting identity
        //    before the flow finishes (see step 7) can leave a half-attested
        //    key in the Keychain: `isAlreadyAttested` would then report `true`,
        //    the warm path would skip `attest()` on the next launch, and
        //    `generateAssertion()` would fail against Apple with
        //    `com.apple.devicecheck.error` on a key that was never actually
        //    attested — with no way to recover short of clearing the Keychain.
        let keyId = try await attestor.generateKey()

        // 3. POST /register
        let register = try await postRegister(RegisterRequest(
            entry: entry,
            keyId: keyId,
            hardwareId: hardwareIdProvider(),
            deviceName: deviceNameProvider(),
            model: modelProvider(),
            osVersion: osVersionProvider(),
            platform: Self.platform
        ))
        let isPending = register.status?.lowercased() == "pending"
        if isPending {
            logger.info("Device registered in pending state — completing attestation before prompting for activation code")
        }

        // 4+5. Attest key with SHA256(challenge)
        guard let challengeData = Data(base64Encoded: challenge.challenge) ?? challenge.challenge.data(using: .utf8) else {
            throw PayabliTTPError.attestationFailed(reason: "Could not decode challenge")
        }
        let clientDataHash = ClientDataHash(Data(SHA256.hash(data: challengeData)))
        let attestation = try await attestor.attestKey(keyId, clientDataHash: clientDataHash)

        // 6. POST /attest — required for both Active and Pending devices; it
        //    creates the `DeviceAttestations` row that `/activate` verifies.
        try await postAttest(AttestRequest(
            challengeId: challenge.challengeId,
            keyId: keyId,
            attestation: attestation,
            deviceId: register.deviceId,
            appId: appId,
            entry: entry,
            platform: Self.platform
        ))

        // 7. Persist identity ONLY now that the attestation is fully confirmed
        //    end-to-end. deviceId is written before we surface pending
        //    activation because `/activate` reads both it and the keyId
        //    assertion from the Keychain.
        try storage.set(register.deviceId, forKey: PayabliKeychainKey.deviceId)
        try storage.set(keyId.rawValue, forKey: PayabliKeychainKey.keyId)

        if isPending {
            logger.info("Attestation stored — device still pending activation")
            throw PayabliTTPError.devicePendingActivation
        }

        logger.info("Attestation completed")
        return AttestationResult(keyId: keyId.rawValue, deviceId: register.deviceId)
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

        do {
            let assertion = try await attestor.generateAssertion(keyId, clientDataHash: clientDataHash)
            return AssertionHeaders(
                assertion: assertion.base64,
                keyId: keyId.rawValue,
                deviceId: deviceId,
                timestamp: timestamp
            )
        } catch {
            // Apple refused to sign with the cached key. This happens when the
            // key was never fully attested (legacy half-attested cache) or when
            // the App Attest environment changed (e.g. development ↔ production).
            // Drop the cached identity so the next `initialize()` runs a clean
            // cold attestation instead of looping forever on an unusable key.
            if (error as NSError).domain == Self.deviceCheckErrorDomain {
                let code = (error as NSError).code
                logger.error("generateAssertion failed with DeviceCheck error (code \(code)) — clearing attestation cache")
                clearCache()
            }
            throw error
        }
    }

    // MARK: - Attest helpers

    static let platform = "Ios"

    static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

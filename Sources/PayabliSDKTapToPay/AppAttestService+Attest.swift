import CryptoKit
import Foundation
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

        // Before anything is minted: state from a previous installation names a
        // key that no longer exists, and its pending slot would be reused.
        beginInstallGeneration()

        // 1. POST /challenge
        let challenge = try await postChallenge(entry: entry)

        // 2. Resolve the App Attest key for this attempt.
        //
        //    The attested `keyId` is deliberately NOT persisted yet. Writing it
        //    before the flow finishes (step 6) can leave a half-attested key in
        //    the Keychain: `isAlreadyAttested` would then report `true`, the
        //    warm path would skip `attest()` on the next launch, and
        //    `generateAssertion()` would fail against Apple with
        //    `com.apple.devicecheck.error` on a key that was never attested.
        //
        //    A freshly generated key IS cached in a separate *pending* slot so
        //    a pre-attest retry (network, `/challenge`, `/register`) can reuse
        //    the same Secure Enclave key instead of minting a new one every
        //    attempt. The pending slot is never read by the warm path, so it
        //    cannot poison assertions.
        let keyId: AppAttestKeyId
        if let pendingKeyId = storage.string(forKey: PayabliKeychainKey.pendingKeyId) {
            keyId = AppAttestKeyId(pendingKeyId)
        } else {
            keyId = try await attestor.generateKey()
            try storage.set(keyId.rawValue, forKey: PayabliKeychainKey.pendingKeyId)
        }

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

        guard let challengeData = Data(base64Encoded: challenge.challenge) ?? challenge.challenge.data(using: .utf8) else {
            throw PayabliTTPError.attestationFailed(reason: "Could not decode challenge")
        }

        // 4. Attest the key. `attestKey` is single-use per key, so drop the
        //    pending slot before attesting: a failure here or at `/attest`
        //    must mint a new key next time rather than replay a burned one.
        //    Pre-attest failures above keep the pending slot for reuse.
        storage.remove(forKey: PayabliKeychainKey.pendingKeyId)
        let clientDataHash = ClientDataHash(Data(SHA256.hash(data: challengeData)))
        let attestation = try await attestor.attestKey(keyId, clientDataHash: clientDataHash)

        // 5. POST /attest — required for both Active and Pending devices; it
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

        // 6. Record the binding only now that attestation is confirmed end to
        //    end. One item, so there is no window in which half an identity is
        //    stored and reads as a whole one. It lands before pending activation
        //    is surfaced, because `/activate` reads the handle back.
        remember(AttestedDevice(entry: entry, deviceId: register.deviceId, keyId: keyId.rawValue))

        if isPending {
            logger.info("Attestation stored — device still pending activation")
            throw PayabliTTPError.devicePendingActivation
        }

        logger.info("Attestation completed")
        return AttestationResult(keyId: keyId.rawValue, deviceId: register.deviceId)
    }

    public func generateAssertion(for entry: String) async throws -> AssertionHeaders {
        guard let binding = bindingStore.load().binding(for: entry) else {
            throw PayabliTTPError.attestationFailed(reason: "Missing attestation state")
        }
        let keyId = AppAttestKeyId(binding.keyId)
        let deviceId = binding.deviceId

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
            // Clear only when the key itself is rejected — never fully attested,
            // or minted in a different App Attest environment — so the next
            // `initialize()` runs a clean cold attestation instead of looping.
            //
            // `DCErrorServerUnavailable` asks for the opposite: retry "using the
            // same key and the same value for the clientDataHash parameter", which
            // "helps to preserve the risk metric for a given device". Clearing
            // there throws away a good key.
            let nsError = error as NSError
            if nsError.domain == Self.deviceCheckErrorDomain {
                if nsError.code == Self.deviceCheckInvalidKeyCode {
                    logger.error("generateAssertion rejected the cached key — clearing this paypoint's binding")
                    clearCache(for: entry)
                } else {
                    logger.error(
                        "generateAssertion failed with DeviceCheck error (code \(nsError.code)) — binding kept"
                    )
                }
            }
            throw error
        }
    }

    // MARK: - Attest helpers

    /// `DCErrorInvalidKey` in `DeviceCheck.framework/Headers/DCError.h`, the one
    /// DeviceCheck error that means the cached key itself is unusable.
    static let deviceCheckInvalidKeyCode = 3

    static let platform = "Ios"

    static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

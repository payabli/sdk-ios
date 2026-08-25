import CryptoKit
import Foundation
import PayabliSDKCore

// MARK: - Attestation flow (PRD §18.1) & per-request assertions (PRD §18.2)

extension AppAttestService {
    /// Apple's DeviceCheck / App Attest error domain (`DCError`). Bridged as a
    /// string so this file needs no `import DeviceCheck` and stays testable on
    /// hosts where `DCAppAttestService` is unavailable.
    static let deviceCheckErrorDomain = "com.apple.devicecheck.error"

    /// One attestation at a time per entry point, across every service in the
    /// process.
    ///
    /// The pending-key lookup and the mint that follows it are separated by an
    /// `await`, and App Attest issues a fresh key on every call, so two callers for
    /// one entry point both mint and both register. A caller for an entry point
    /// already being attested waits for that attempt to end and then runs its own,
    /// which reads the store first. Different entry points never wait for each
    /// other.
    public func attest(entry: String, appId: String) async throws -> AttestationResult {
        try await Self.attestations.takingTurns(entry) {
            try await self.runAttest(entry: entry, appId: appId)
        }
    }

    private func runAttest(entry: String, appId: String) async throws -> AttestationResult {
        // Read inside the gate: the caller's warm check ran outside it, and an
        // attempt that finished in between leaves a binding this one would
        // otherwise register a second device to replace. Answering from the binding
        // claims no activation; `/config` answers for it as it does on the warm
        // path.
        if let held = try binding(for: entry), await keyIsStillHeld(held) {
            logger.info("[attest] this paypoint was enrolled while this attempt waited")
            return AttestationResult(keyId: held.keyId, deviceId: held.deviceId)
        }

        guard attestor.isSupported else {
            throw PayabliTTPError.attestationFailed(reason: "App Attest not supported on this device")
        }

        // 1. POST /challenge
        let challenge = try await postChallenge(entry: entry)

        // 2. Resolve the App Attest key for this attempt.
        //
        //    The attested `keyId` is not persisted until step 6: a binding written
        //    earlier reads as complete, so the next launch skips `attest()` and
        //    signs with a key that was never attested.
        //
        //    A freshly generated key is kept in a separate pending slot, per entry
        //    point, so a pre-attest retry reuses the same Secure Enclave key. A key
        //    can be attested once, so two paypoints enrolling cannot share one. The
        //    warm path never reads the slot.
        let keyId: AppAttestKeyId
        if let pending = try pendingKey(for: entry) {
            keyId = AppAttestKeyId(pending)
        } else {
            keyId = try await attestor.generateKey()
            try rememberPendingKey(keyId.rawValue, for: entry)
        }

        // 3. POST /register
        let register = try await postRegister(RegisterRequest(
            entry: entry,
            keyId: keyId,
            hardwareId: try hardwareId(),
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
        //    pending slot before attesting: a failure here or at `/attest` mints
        //    a new key next time, since a burned one is refused. Pre-attest
        //    failures above keep the slot for reuse.
        //
        //    Raises on a drop that did not land: the key is about to be spent, and
        //    a surviving record is one the next attempt reuses and is refused for.
        try forgetPendingKey(for: entry)
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

        // 6. Record the binding once attestation is confirmed end to end. One item,
        //    so no window stores half an identity that reads as a whole one, and it
        //    lands before pending activation is surfaced: `/activate` reads the
        //    handle back.
        try remember(AttestedDevice(entry: entry, deviceId: register.deviceId, keyId: keyId.rawValue))

        if isPending {
            logger.info("Attestation stored — device still pending activation")
            throw PayabliTTPError.devicePendingActivation
        }

        logger.info("Attestation completed")
        return AttestationResult(keyId: keyId.rawValue, deviceId: register.deviceId)
    }

    public func generateAssertion(for entry: String) async throws -> AssertionHeaders {
        guard let binding = try binding(for: entry) else {
            throw PayabliTTPError.attestationFailed(reason: "Missing attestation state")
        }
        let keyId = AppAttestKeyId(binding.keyId)
        let deviceId = binding.deviceId

        // The server verifies the assertion against `X-Assertion-Timestamp`, so
        // client-data is the SHA-256 of the same ISO-8601 string that is sent.
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
            // Clear only when the key itself is rejected, so the next
            // `initialize()` runs a cold attestation.
            let nsError = error as NSError
            if nsError.domain == Self.deviceCheckErrorDomain {
                if Self.deviceCheckUnusableKeyCodes.contains(nsError.code) {
                    logger.error("generateAssertion cannot use the stored key — clearing this paypoint's binding")
                    // The binding read at the top of this call: the attempt
                    // suspends, and one finishing in that window leaves a
                    // binding this answer is not about.
                    forgetIfUnchanged(binding)
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

    /// The DeviceCheck codes that say this device cannot produce an assertion for
    /// the key it was asked about, from `DeviceCheck.framework/Headers/DCError.h`.
    ///
    /// `DCErrorInvalidKey` is the documented one. A key that no longer exists
    /// reports `DCErrorInvalidInput`, which the documentation describes as
    /// malformed data; the only data here besides the identifier is a SHA-256 hash.
    /// `DCErrorUnknownSystemFailure` is what an unattested key reports and belongs
    /// to the pending slot, and `DCErrorServerUnavailable` asks for a retry with
    /// the same key to preserve the device's risk metric.
    static let deviceCheckUnusableKeyCodes: Set<Int> = [2, 3]

    static let platform = "Ios"

    /// Shared by every service in the process: a facade builds its own, and a host
    /// talking to one paypoint from two places builds two.
    static let attestations = AttestationsInFlight()

    static let iso8601WithFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
}

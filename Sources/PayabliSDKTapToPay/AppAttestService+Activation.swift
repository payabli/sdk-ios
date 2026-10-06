import Foundation
import PayabliSDKCore

// MARK: - Device activation (PRD §9.7)

package extension AppAttestService {
    /// Takes the entry point's turn, as attestation does, so no enrollment replaces the
    /// registration while its code is being spent.
    func activateDevice(activationCode: String, entry: String, activationId: String) async throws {
        try await Self.attestations.takingTurns(entry) {
            try await self.runActivate(activationCode: activationCode, entry: entry, activationId: activationId)
        }
    }

    private func runActivate(activationCode: String, entry: String, activationId: String) async throws {
        // Read only to refuse a paypoint that holds no binding. The handle sent is
        // the assertion's, below.
        guard let held = try cachedDeviceId(for: entry) else {
            throw PayabliTTPError.attestationFailed(reason: "Missing deviceId — run initialize() before activateDevice")
        }
        guard held == activationId else {
            throw ActivationRegistrationChanged()
        }

        // Rotate the nonce before `/activate` verifies the assertion. The
        // returned payload is unused here, since the assertion is signed over a
        // fresh timestamp rather than the challenge.
        _ = try await postChallenge(entry: entry)

        let assertion = try await generateAssertion(for: entry)
        // Read again once signed: a refusal elsewhere can drop the binding while the platform signs,
        // and the turn does not cover that.
        guard assertion.deviceId == activationId, try cachedDeviceId(for: entry) == activationId else {
            throw ActivationRegistrationChanged()
        }

        // The assertion's handle, so the body and the headers come from one
        // binding. Read separately they can name two devices.
        try await postAttestationRequestExpectingNoBody(
            path: "/api/v2/device/taptopay/activate",
            body: ActivateRequest(entry: entry, deviceId: assertion.deviceId, activationCode: activationCode),
            label: "activate",
            assertion: assertion,
            makeDeclineError: { code, reason in
                // A 401 here means this keyId has no attestation on record, so
                // the binding names a key that buys nothing. Drop it and let the
                // next `initialize()` enrol.
                if code == 401 {
                    self.logger.error("[activate] clearing local attestation cache and signaling attestationRevoked")
                    // The binding this assertion named, not whatever is held now.
                    let refused = AttestedDevice(
                        entry: entry,
                        deviceId: assertion.deviceId,
                        keyId: assertion.keyId
                    )
                    do {
                        try self.forgetRefused(refused)
                    } catch {
                        // Revoked either way, and the caller is told which. A
                        // binding left behind is presented again on the next warm
                        // check.
                        return .attestationRevoked(
                            reason: "\(reason) — the stored binding could not be dropped"
                        )
                    }
                    return .attestationRevoked(reason: reason)
                }
                return .activationFailed(reason: reason)
            }
        )
    }
}

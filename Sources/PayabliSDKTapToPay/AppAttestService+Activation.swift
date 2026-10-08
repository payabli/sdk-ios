import Foundation
import PayabliSDKCore

// MARK: - Device activation (PRD §9.7)

package extension AppAttestService {
    func activateDevice(activationCode: String, entry: String, activationId: String) async throws {
        try await Self.attestations.takingTurns(entry) {
            try await self.runActivate(activationCode: activationCode, entry: entry, activationId: activationId)
        }
    }

    private func runActivate(activationCode: String, entry: String, activationId: String) async throws {
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

        let assertion = try await signingActivation(entry: entry)
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
            readsRefusalBeforeStatus: true,
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
                        return PayabliTTPError.attestationRevoked(
                            reason: "\(reason) — the stored binding could not be dropped"
                        )
                    }
                    return PayabliTTPError.attestationRevoked(reason: reason)
                }
                if ActivationRefusals.discardsBinding(resultCode: code, reason: reason) {
                    // The binding this assertion named, not whatever is held now.
                    let unknown = AttestedDevice(entry: entry, deviceId: assertion.deviceId, keyId: assertion.keyId)
                    do {
                        try self.forgetRefused(unknown)
                    } catch {
                        // Setting the device up again needs the binding gone, so a binding that stays is the
                        // failure the caller has to hear.
                        self.logger.error("[activate] the binding the service does not know could not be dropped")
                        return error
                    }
                }
                return ActivationRefusals.refusal(resultCode: code, reason: reason)
            }
        )
    }

    /// The assertion `/activate` is signed with, or a failure that says nothing was sent.
    ///
    /// The binding is already dropped for a key the platform no longer holds, so that refusal is a
    /// setup that has ended.
    private func signingActivation(entry: String) async throws -> AssertionHeaders {
        do {
            return try await generateAssertion(for: entry)
        } catch let error as CancellationError {
            throw error
        } catch let error as TapToPayError {
            throw ActivationSigningFailed(hostError: error)
        } catch PayabliTTPError.attestationFailed {
            throw ActivationSigningFailed(hostError: TapToPayError(
                type: .deviceSetupRequired,
                reason: "No device binding is held to sign the activation with",
                detail: nil
            ))
        } catch {
            let nsError = error as NSError
            let keyIsGone = nsError.domain == Self.deviceCheckErrorDomain
                && Self.deviceCheckUnusableKeyCodes.contains(nsError.code)
            throw ActivationSigningFailed(hostError: TapToPayError(
                type: keyIsGone ? .deviceSetupRequired : .sdkInternalError,
                reason: "The activation could not be signed",
                detail: "\(nsError.domain) \(nsError.code)"
            ))
        }
    }
}

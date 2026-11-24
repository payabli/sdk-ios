import Foundation
import PayabliSDKCore

// MARK: - Device activation

package extension AppAttestService {
    func activateDevice(activationCode: String, entry: String, activationId: String) async throws {
        try await Self.attestations.takingTurns(entry) {
            try await self.runActivate(activationCode: activationCode, entry: entry, activationId: activationId)
        }
    }

    private func runActivate(activationCode: String, entry: String, activationId: String) async throws {
        guard let held = try cachedDeviceId(for: entry) else {
            throw PayabliTTPError.deviceSetupRequired(reason: "Missing deviceId — run initialize() before activateDevice")
        }
        guard held == activationId else {
            throw ActivationRegistrationChanged()
        }

        let assertion = try await signingActivation(entry: entry)
        guard assertion.deviceId == activationId, try cachedDeviceId(for: entry) == activationId else {
            throw ActivationRegistrationChanged()
        }

        do {
            try await postActivate(activationCode: activationCode, entry: entry, assertion: assertion)
        } catch let refusal as DeviceRouteRefusal where refusal.type == .deviceSetupRequired {
            // A 401 whose envelope names another code is read by its status: the service holds no attestation for this
            // key, so the session stops waiting for a code. A store that refuses the drop leaves the refusal unchanged.
            do {
                try forgetRefused(AttestedDevice(entry: entry, deviceId: assertion.deviceId, keyId: assertion.keyId))
            } catch {
                logger.error("[activate] the refused binding could not be dropped")
            }
            throw ActivationRefusals.deviceRefused(refusal)
        } catch let refusal as DeviceRouteRefusal {
            // An envelope naming another code than its status: no status names one activation refusal, so the
            // binding is kept and the code is still owed.
            guard let status = refusal.httpStatus, [400, 403, 404].contains(status) else { throw refusal }
            throw ActivationRefusals.readByStatus(status)
        }
    }

    /// Sends `/activate` signed by `assertion`, and classifies its refusal.
    ///
    /// - Parameter activationCode: the code the payer entered.
    /// - Parameter entry: the entry point being activated.
    /// - Parameter assertion: the assertion the activation is signed with.
    private func postActivate(activationCode: String, entry: String, assertion: AssertionHeaders) async throws {
        // The assertion's handle, so the body and the headers come from one
        // binding. Read separately they can name two devices.
        try await postAttestationRequestExpectingNoBody(
            .activate,
            path: "/api/v2/device/taptopay/activate",
            body: ActivateRequest(entry: entry, deviceId: assertion.deviceId, activationCode: activationCode),
            assertion: assertion,
            readsRefusalBeforeStatus: true,
            isCredentialPinned: true,
            makeDeclineError: { code, reason in
                // The service holds no attestation for this key, so the binding names a key that buys nothing. Drop
                // it and let the next `initialize()` enrol.
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

    /// The assertion `/activate` is signed with, or a failure that says `/activate` was not sent.
    ///
    /// The binding is already dropped for a key the platform no longer holds, so that refusal is a
    /// setup that has ended.
    ///
    /// - Parameter entry: the entry point whose stored binding signs the activation.
    /// - Returns: the assertion to sign `/activate` with, or the failure that says it was not sent.
    private func signingActivation(entry: String) async throws -> AssertionHeaders {
        do {
            return try await generateAssertion(for: entry)
        } catch let error as CancellationError {
            throw error
        } catch let error as TapToPayError {
            throw ActivationSigningFailed(hostError: error)
        } catch PayabliTTPError.deviceSetupRequired {
            throw ActivationSigningFailed(hostError: TapToPayError(
                type: .deviceSetupRequired,
                reason: "No device binding is held to sign the activation with",
                detail: nil
            ))
        } catch {
            let nsError = error as NSError
            throw ActivationSigningFailed(hostError: TapToPayError(
                type: .sdkInternalError,
                reason: "The activation could not be signed",
                detail: "\(nsError.domain) \(nsError.code)"
            ))
        }
    }
}

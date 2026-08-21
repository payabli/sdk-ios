import Foundation
import PayabliSDKCore

// MARK: - Device activation (PRD §9.7)

public extension AppAttestService {
    func activateDevice(activationCode: String, entry: String) async throws {
        guard let deviceId = cachedDeviceId(for: entry) else {
            throw PayabliTTPError.attestationFailed(reason: "Missing deviceId — run initialize() before activateDevice")
        }

        // Rotate the server-side nonce before `/activate` verifies our
        // assertion. The returned payload is unused client-side because the
        // assertion is signed over a fresh timestamp, not the challenge.
        _ = try await postChallenge(entry: entry)

        let assertion = try await generateAssertion(for: entry)

        try await postAttestationRequestExpectingNoBody(
            path: "/api/v2/device/taptopay/activate",
            body: ActivateRequest(entry: entry, deviceId: deviceId, activationCode: activationCode),
            label: "activate",
            assertion: assertion,
            makeDeclineError: { code, reason in
                // 401 means the server has no active `DeviceAttestations` row
                // for our keyId (e.g. a previous `/attest` was rolled back due
                // to a paypoint misconfiguration). The cached keyId/deviceId
                // are useless; wipe them and force a fresh `initialize()`.
                if code == 401 {
                    self.logger.error("[activate] clearing local attestation cache and signaling attestationRevoked")
                    self.clearCache(for: entry)
                    return .attestationRevoked(reason: reason)
                }
                return .activationFailed(reason: reason)
            }
        )
    }
}

import Foundation
import PayabliSDKCore

// MARK: - Device activation (PRD §9.7)

public extension AppAttestService {
    func activateDevice(activationCode: String, entry: String) async throws {
        guard let deviceId = cachedDeviceId(for: entry) else {
            throw PayabliTTPError.attestationFailed(reason: "Missing deviceId — run initialize() before activateDevice")
        }

        // Rotate the nonce before `/activate` verifies the assertion. The
        // returned payload is unused here, since the assertion is signed over a
        // fresh timestamp rather than the challenge.
        _ = try await postChallenge(entry: entry)

        let assertion = try await generateAssertion(for: entry)

        try await postAttestationRequestExpectingNoBody(
            path: "/api/v2/device/taptopay/activate",
            body: ActivateRequest(entry: entry, deviceId: deviceId, activationCode: activationCode),
            label: "activate",
            assertion: assertion,
            makeDeclineError: { code, reason in
                // A 401 here means this keyId has no attestation on record, so
                // the binding names a key that buys nothing. Drop it and let the
                // next `initialize()` enrol.
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

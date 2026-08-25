import Foundation
import PayabliSDKCore

// MARK: - Device activation (PRD §9.7)

public extension AppAttestService {
    func activateDevice(activationCode: String, entry: String) async throws {
        // Read only to refuse a paypoint that holds no binding. The handle sent is
        // the assertion's, below.
        guard try cachedDeviceId(for: entry) != nil else {
            throw PayabliTTPError.attestationFailed(reason: "Missing deviceId — run initialize() before activateDevice")
        }

        // Rotate the nonce before `/activate` verifies the assertion. The
        // returned payload is unused here, since the assertion is signed over a
        // fresh timestamp rather than the challenge.
        _ = try await postChallenge(entry: entry)

        let assertion = try await generateAssertion(for: entry)

        // The assertion's handle, not one read before two suspensions. It comes
        // from the same binding as the key that signed, so the body and the headers
        // describe one device. Read separately they can name two, and a request
        // whose body and signature disagree is refused for a reason neither names.
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
                    do {
                        try self.clearCache(for: entry)
                    } catch {
                        // Revoked either way, and the caller is told which. A
                        // binding left behind names a key the platform still signs
                        // with, so the next warm check trusts it and presents the
                        // same refused handle.
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

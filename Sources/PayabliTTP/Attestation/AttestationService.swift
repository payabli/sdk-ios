import Foundation

/// Handles all device attestation API calls:
/// challenge, attest, and config (fetch Fiserv credentials).
/// Uses `requestToken` header (value: apiKey) for authentication on all 3 endpoints.
final class AttestationService {

    private let http: Networking

    init(http: Networking) {
        self.http = http
    }

    /// Request a cryptographic nonce from the backend for App Attest key attestation.
    func fetchChallenge() async throws -> ChallengeResponse {
        let request = try http.buildRequest(
            endpoint: .challenge,
            authHeader: ("requestToken", http.configuration.apiKey)
        )
        return try await http.executePayabli(request)
    }

    /// Register the attested key with the backend.
    /// Sends challengeId so the backend can verify the nonce it issued,
    /// keyId + attestation for cryptographic verification, and deviceId (poi_id) to link
    /// the attestation record to the registered device.
    @discardableResult
    func registerAttestation(challengeId: String, keyId: String, attestation: Data, deviceId: String) async throws -> AttestResponse {
        let body = AttestRequest(
            challengeId: challengeId,
            keyId: keyId,
            attestation: attestation.base64EncodedString(),
            deviceId: deviceId
        )
        var request = try http.buildRequest(
            endpoint: .attest,
            authHeader: ("requestToken", http.configuration.apiKey)
        )
        request.httpBody = try http.encode(body)
        return try await http.executePayabli(request)
    }

    /// Fetch Fiserv credentials + requestToken. Requires a valid assertion
    /// to prove device identity. Returns ephemeral config (never persisted).
    func fetchConfig(assertion: Data, keyId: String, deviceId: String) async throws -> ConfigResponse {
        var request = try http.buildRequest(
            endpoint: .config(entry: http.configuration.entry),
            authHeader: ("requestToken", http.configuration.apiKey)
        )
        request.setValue(assertion.base64EncodedString(), forHTTPHeaderField: "X-App-Assertion")
        request.setValue(keyId, forHTTPHeaderField: "X-App-KeyId")
        request.setValue(deviceId, forHTTPHeaderField: "X-Device-Id")
        return try await http.execute(request)
    }
}

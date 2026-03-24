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

    /// Register the attested key (keyId + attestation object) with the backend.
    /// Also sends deviceId so the backend can link the attestation to the registered device.
    func registerAttestation(keyId: String, attestation: Data, deviceId: String) async throws {
        let body = AttestRequest(keyId: keyId, attestation: attestation.base64EncodedString(), deviceId: deviceId)
        var request = try http.buildRequest(
            endpoint: .attest,
            authHeader: ("requestToken", http.configuration.apiKey)
        )
        request.httpBody = try http.encode(body)
        try await http.executeVoid(request)
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

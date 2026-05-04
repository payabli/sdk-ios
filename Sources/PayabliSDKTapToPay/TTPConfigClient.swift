import Foundation
import PayabliSDKCore

/// Provider-agnostic shape of the runtime config returned by
/// `GET /api/v2/device/taptopay/config/{entry}`.
///
/// The PRD leaves the exact shape flexible because it contains processor-specific
/// credentials (Fiserv in v1.0). We model it as a loose dictionary that the
/// concrete provider adapter interprets. See FR-11B.3, NFR-5D.
public struct TTPConfig: Sendable {
    public let paymentToken: String?
    public let providerCredentials: [String: String]
}

/// Client for the attestation-protected config endpoint (PRD §8.2).
///
/// Requires `X-App-Assertion`, `X-App-KeyId`, `X-Device-Id`, `X-Assertion-Timestamp`.
public final class TTPConfigClient: Sendable {
    private let service: PayabliService
    private let auth: PayabliAuth
    private let attestation: DeviceAttestationService
    private let logger = PayabliLogger(category: .taptopay)

    public init(
        service: PayabliService,
        auth: PayabliAuth,
        attestation: DeviceAttestationService
    ) {
        self.service = service
        self.auth = auth
        self.attestation = attestation
    }

    /// Fetches the TTP config for the given `entry`. On 401, throws
    /// `.tokenExpired` — callers should clear attestation cache and re-attest
    /// (PRD §18.4).
    ///
    /// The SDK flattens `credentials` into `TTPConfig.providerCredentials`
    /// for the TapToPayProvider to consume.
    public func fetchConfig(entry: String) async throws -> TTPConfig {
        let headers = try await assertionHeaders()
        let token = await auth.currentAccessToken()

        let merged = headers.asDictionary.merging(["Authorization": "Bearer \(token)"]) { current, _ in current }

        let request = PayabliRequest(
            method: .get,
            path: "/api/v2/device/taptopay/config/\(entry)",
            headers: merged
        )

        let headersDump = merged
            .map { "\($0.key): \($0.value)" }
            .sorted()
            .joined(separator: " | ")
        logger.info("[config] → GET \(request.path)")
        logger.info("[config] headers: \(headersDump)")

        let response = try await service.perform(request)

        let responseBody = String(data: response.body, encoding: .utf8) ?? "<non-utf8 \(response.body.count) bytes>"
        logger.info("[config] ← [\(response.statusCode)] body: \(responseBody)")

        if response.statusCode == 401 {
            throw PayabliGenericError(code: .tokenExpired, reason: "Config endpoint returned 401")
        }
        if response.statusCode == 403 {
            throw PayabliTTPError.devicePendingActivation
        }
        guard (200..<300).contains(response.statusCode) else {
            throw PayabliTTPError.configFailed(reason: "HTTP \(response.statusCode)")
        }

        // Shared envelope helpers live in `PayabliSDKCore/Networking/ResponseEnvelope.swift`.
        if let (rawCode, reason) = PayabliEnvelope.declineOutcome(from: response.body) {
            let code = rawCode ?? 0
            logger.error("[config] declined (isSuccess=false code=\(code)): \(reason)")
            // 401 semantics from the server body: attestation was revoked or
            // device not attested → caller should clear cache and re-attest.
            if code == 401 {
                throw PayabliGenericError(code: .tokenExpired, reason: reason)
            }
            if code == 403 {
                throw PayabliTTPError.devicePendingActivation
            }
            throw PayabliTTPError.configFailed(reason: reason)
        }

        let decoder = JSONDecoder()
        guard let envelope = try? decoder.decode(
                PayabliEnvelope.Success<ConfigCredentialsPayload>.self,
                from: response.body
              ),
              let credentials = envelope.responseData?.credentials else {
            logger.error("[config] payload decode failed")
            throw PayabliTTPError.configFailed(reason: "Invalid config envelope")
        }

        return TTPConfig(
            paymentToken: nil,
            providerCredentials: credentials
        )
    }

    private func assertionHeaders() async throws -> AssertionHeaders {
        try await attestation.generateAssertion()
    }
}

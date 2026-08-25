import Foundation
import PayabliSDKCore

/// Provider-agnostic shape of the runtime config returned by
/// `GET /api/v2/device/taptopay/config/{entry}`.
///
/// The PRD leaves the exact shape flexible because it contains processor-specific
/// credentials (Fiserv in v1.0), so it arrives as a loose dictionary that the
/// concrete provider adapter interprets. See FR-11B.3, NFR-5D.
public struct TTPConfig: Sendable {
    public let paymentToken: String?
    public let providerCredentials: [String: String]
}

/// Client for the attestation-protected config endpoint (PRD §8.2).
///
/// Requires `X-App-Assertion`, `X-App-KeyId`, `X-Device-Id`, `X-Assertion-Timestamp`.
/// Bearer-auth injection and HTTP 401 refresh-and-retry are delegated to the
/// `PayabliTransport` passed at init — callers should supply `session.transport`.
/// Attestation headers are component-specific and are added inline.
public final class TTPConfigClient: Sendable {
    private let transport: any PayabliTransport
    private let attestation: DeviceAttestationService
    private let logger = PayabliLogger(category: .taptopay)

    public init(
        transport: any PayabliTransport,
        attestation: DeviceAttestationService
    ) {
        self.transport = transport
        self.attestation = attestation
    }

    /// Fetches the TTP config for the given `entry`. On 401 (after transport
    /// refresh-and-retry exhaustion), the underlying `PayabliGenericError(.tokenExpired)`
    /// propagates — callers should clear attestation cache and re-attest (PRD §18.4).
    ///
    /// The SDK flattens `credentials` into `TTPConfig.providerCredentials`
    /// for the TapToPayProvider to consume.
    public func fetchConfig(entry: String) async throws -> TTPConfig {
        let headers = try await assertionHeaders(entry: entry)

        // Attestation headers are component-specific; bearer is added by the transport.
        let request = PayabliRequest(
            method: .get,
            path: "/api/v2/device/taptopay/config/\(entry)",
            headers: headers.asDictionary
        )

        // The headers carry the App Attest assertion, key id and device id.
        logger.info("[config] → GET \(request.path)")

        let response = try await transport.perform(request)

        // This body is `ConfigCredentialsPayload`, whose `credentials` block
        // carries the card reader's secretKey and apiKey. The log gets its shape.
        logger.info("[config] ← [\(response.statusCode)] bytes=\(response.body.count)")

        try mapPayabliHTTPError(response: response) { code in
            if code == 403 {
                return PayabliTTPError.devicePendingActivation
            }
            return nil
        }

        // Shared envelope helpers live in `PayabliSDKCore/Networking/ResponseEnvelope.swift`.
        if let (rawCode, reason) = PayabliEnvelope.declineOutcome(from: response.body) {
            let code = rawCode ?? 0
            // Same as the attestation path: the code, not the service's sentence.
            logger.error("[config] declined (isSuccess=false code=\(code))")
            // A 401 in the body refuses the binding this request presented, so
            // it is dropped here, where which handle that was is known.
            if code == 401 {
                dropRefusedBinding(entry: entry, presented: headers.deviceId)
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
            let credentials = envelope.responseData?.credentials
        else {
            logger.error("[config] payload decode failed")
            throw PayabliTTPError.configFailed(reason: "Invalid config envelope")
        }

        return TTPConfig(
            paymentToken: nil,
            providerCredentials: credentials
        )
    }

    private func assertionHeaders(entry: String) async throws -> AssertionHeaders {
        try await attestation.generateAssertion(for: entry)
    }

    /// Drops the refused binding while it is still the one held, and never fails
    /// the caller, which is already reporting the refusal.
    private func dropRefusedBinding(entry: String, presented deviceId: String) {
        do {
            guard try attestation.cachedDeviceId(for: entry) == deviceId else {
                logger.info("[config] a newer binding is held for this paypoint; keeping it")
                return
            }
            try attestation.clearCache(for: entry)
        } catch {
            logger.info("[config] the refused binding could not be dropped")
        }
    }
}

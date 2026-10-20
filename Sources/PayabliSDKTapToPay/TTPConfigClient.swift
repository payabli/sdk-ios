import Foundation
import PayabliSDKCore

/// Provider-agnostic runtime config from `GET /api/v2/device/taptopay/config/{entry}`. It carries
/// processor-specific credentials (Fiserv), so it is a loose dictionary the provider adapter interprets.
struct TTPConfig: Sendable {
    let providerCredentials: [String: String]
}

/// Client for the attestation-protected config endpoint; adds the `X-App-*`, `X-Device-Id` and
/// `X-Assertion-Timestamp` headers inline. Bearer auth and HTTP 401 refresh-and-retry come from the
/// `PayabliTransport` passed at init, which should be `session.transport`.
final class TTPConfigClient: Sendable {
    private let transport: any PayabliTransport
    private let attestation: DeviceAttestationService
    private let logger = PayabliLogger(category: .taptopay)

    init(
        transport: any PayabliTransport,
        attestation: DeviceAttestationService
    ) {
        self.transport = transport
        self.attestation = attestation
    }

    /// Fetches the TTP config for `entry`. A 401 inside a 200 envelope drops the binding so the next
    /// `initialize()` enrols. An HTTP 401 surviving refresh drops nothing: clearing on it retires an enrolled
    /// device. Both throw `PayabliGenericError(.tokenExpired)`, whose reason names which happened.
    ///
    /// - Parameter entry: the entry point whose configuration is fetched.
    /// - Returns: the route's configuration, carrying the reader credentials.
    func fetchConfig(entry: String) async throws -> TTPConfig {
        let headers = try await assertionHeaders(entry: entry)

        // Attestation headers are component-specific; bearer is added by the transport.
        let request = PayabliRequest(
            method: .get,
            path: "/api/v2/device/taptopay/config/\(PercentEncoding.segment(entry))",
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
                return ConfigPendingActivation(presentedDeviceId: headers.deviceId)
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
                guard dropRefusedBinding(entry: entry, presented: headers) else {
                    throw PayabliGenericError(
                        type: .tokenExpired,
                        reason: "\(reason) — the stored binding could not be dropped"
                    )
                }
                throw PayabliGenericError(type: .tokenExpired, reason: reason)
            }
            if code == 403 {
                throw ConfigPendingActivation(presentedDeviceId: headers.deviceId)
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

        return TTPConfig(providerCredentials: credentials)
    }

    private func assertionHeaders(entry: String) async throws -> AssertionHeaders {
        try await attestation.generateAssertion(for: entry)
    }

    /// Drops the refused binding while it is still the one held.
    ///
    /// `true` covers a removed binding and a newer one kept; `false` is only a store that refused.
    ///
    /// - Parameter entry: the entry point the refused binding names.
    /// - Parameter headers: the assertion headers this request presented, naming the device and key the refusal was about.
    /// - Returns: whether the paypoint was left in a state the caller need not report.
    private func dropRefusedBinding(entry: String, presented headers: AssertionHeaders) -> Bool {
        do {
            let dropped = try attestation.forgetRefusedBinding(
                entry: entry,
                deviceId: headers.deviceId,
                keyId: headers.keyId
            )
            if !dropped {
                logger.info("[config] a newer binding is held for this paypoint; keeping it")
            }
            return true
        } catch {
            logger.error("[config] the refused binding could not be dropped")
            return false
        }
    }
}

struct ConfigPendingActivation: Error {
    let presentedDeviceId: String
}

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
    private let routes: DeviceServiceClient
    private let attestation: DeviceAttestationService
    private let logger: PayabliLogger

    /// - Parameter transport: what the request is sent over, the session's.
    /// - Parameter attestation: what signs the request's assertion.
    /// - Parameter telemetrySession: the session the route's report belongs to; `nil` for the installed one.
    /// - Parameter logger: where the route call and its outcome are logged.
    init(
        transport: any PayabliTransport,
        attestation: DeviceAttestationService,
        telemetrySession: TelemetrySessionContext? = nil,
        logger: PayabliLogger = PayabliLogger(category: .taptopay)
    ) {
        routes = DeviceServiceClient(transport: transport, telemetrySession: telemetrySession, logger: logger)
        self.attestation = attestation
        self.logger = logger
    }

    /// Fetches the TTP config for `entry` on a pinned credential. An envelope naming 401, or any coded envelope at status 401,
    /// drops the binding presented and throws `attestationRevoked` (3005 to a host); only a bare 401 is ``PinnedTokenRefusal``.
    /// A 403 naming the entry point throws `entryPointRefused`; one naming nothing classified is the device owing its code.
    ///
    /// - Parameter entry: the entry point whose configuration is fetched.
    /// - Returns: the route's configuration, carrying the reader credentials.
    func fetchConfig(entry: String) async throws -> TTPConfig {
        let headers = try await assertionHeaders(entry: entry)

        // Attestation headers are component-specific; bearer is added by the transport.
        let request = PayabliRequest(
            method: .get,
            path: PercentEncoding.path(from: DeviceRoute.config.template, segment: PercentEncoding.segment(entry)),
            route: DeviceRoute.config.template,
            headers: headers.asDictionary,
            isCredentialPinned: true
        )

        return try await routes.measured(.config) {
            let response = try await routes.get(.config, request)

            try throwRefusalToldByItsText(response, entry: entry, presented: headers)
            if response.statusCode == 401 {
                // An envelope naming a code is the route's refusal, read by its status; only a bare 401 is the token.
                if let (code, reason) = PayabliEnvelope.declineOutcome(from: response.body), code != nil {
                    throw refusedBinding(reason: reason, httpStatus: 401, entry: entry, presented: headers)
                }
                throw PinnedTokenRefusal()
            }

            // A refusal naming no code is left to the status mapping below; one whose code is not its status is classified
            // by the status.
            if [400, 404].contains(response.statusCode),
               let (code, reason) = PayabliEnvelope.declineOutcome(from: response.body), let code
            {
                let read = code == response.statusCode ? ColdRouteRefusals.decline(code: code, reason: reason) : nil
                let refused = read
                    ?? DeviceRouteRefusal.of(code: response.statusCode, reason: reason, httpStatus: response.statusCode)
                throw DeviceRefusalStatus.carrying(response.statusCode, on: refused)
            }
            try mapPayabliHTTPError(response: response) { code in
                if code == 403 {
                    return ConfigPendingActivation(presentedDeviceId: headers.deviceId, httpStatus: code)
                }
                return nil
            }

            // Shared envelope helpers live in `PayabliSDKCore/Networking/ResponseEnvelope.swift`.
            if let (rawCode, reason) = PayabliEnvelope.declineOutcome(from: response.body) {
                let code = rawCode ?? 0
                // Same as the attestation path: the code, not the service's sentence.
                logger.error("[config] declined (isSuccess=false code=\(code))")
                // A 401 in the body is the service holding no live attestation for the binding, whatever its text. It is
                // dropped here, where which handle the request presented is known, so the next setup attests again.
                if code == 401 {
                    throw refusedBinding(reason: reason, httpStatus: response.statusCode, entry: entry, presented: headers)
                }
                if let refused = ColdRouteRefusals.decline(code: code, reason: reason) {
                    throw DeviceRefusalStatus.carrying(response.statusCode, on: refused)
                }
                if code == 403 {
                    throw ConfigPendingActivation(presentedDeviceId: headers.deviceId, httpStatus: response.statusCode)
                }
                throw DeviceRouteRefusal.of(code: rawCode, reason: reason, httpStatus: response.statusCode)
            }

            let decoder = JSONDecoder()
            guard let envelope = try? decoder.decode(
                PayabliEnvelope.Success<ConfigCredentialsPayload>.self,
                from: response.body
            ),
                let credentials = envelope.responseData?.credentials
            else {
                logger.error("[config] payload decode failed")
                throw DeviceRouteRefusal.undecodable(httpStatus: response.statusCode)
            }

            return TTPConfig(providerCredentials: credentials)
        }
    }

    /// Throws the refusals told apart by their text before the status is mapped: an app the paypoint has not registered,
    /// an entry point the request may not use, and a binding the service no longer holds, which is dropped here while
    /// the handle the request presented is known. Only an envelope whose code is its status is read here.
    ///
    /// - Parameter response: the answer to the config request.
    /// - Parameter entry: the entry point the request was made for.
    /// - Parameter headers: the assertion the request carried, naming the binding it presented.
    private func throwRefusalToldByItsText(
        _ response: PayabliResponse,
        entry: String,
        presented headers: AssertionHeaders
    ) throws {
        guard let (code, reason) = PayabliEnvelope.declineOutcome(from: response.body), code == response.statusCode else {
            return
        }
        if let unregistered = AppRegistrationRefusals.hostError(status: response.statusCode, reason: reason) {
            logger.error("[config] refused: the app is not registered on the paypoint")
            throw unregistered
        }
        if let refused = ColdRouteRefusals.decline(code: response.statusCode, reason: reason) {
            logger.error("[config] refused: the entry point is not available")
            throw DeviceRefusalStatus.carrying(response.statusCode, on: refused)
        }
        // A 401 naming 401 is the service holding no live attestation for this binding, whatever its words.
        guard code == 401 else { return }
        logger.error("[config] the service holds no live attestation for this binding")
        throw refusedBinding(reason: reason, httpStatus: response.statusCode, entry: entry, presented: headers)
    }

    /// Drops the binding a refused request presented and builds the failure that says so.
    ///
    /// - Parameter reason: the service's words, kept as the failure's reason.
    /// - Parameter httpStatus: the status the refusal came with.
    /// - Parameter entry: the entry point the refused binding names.
    /// - Parameter headers: the assertion headers the request presented.
    /// - Returns: `attestationRevoked`, whose reason says when the stored binding could not be dropped.
    private func refusedBinding(
        reason: String,
        httpStatus: Int,
        entry: String,
        presented headers: AssertionHeaders
    ) -> PayabliTTPError {
        guard dropRefusedBinding(entry: entry, presented: headers) else {
            return .attestationRevoked(reason: "\(reason) — the stored binding could not be dropped", httpStatus: httpStatus)
        }
        return .attestationRevoked(reason: reason, httpStatus: httpStatus)
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
    let httpStatus: Int
}

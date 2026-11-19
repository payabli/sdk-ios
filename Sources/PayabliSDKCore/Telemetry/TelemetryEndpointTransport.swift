import Foundation

/// Posts telemetry batches through the SDK's own request path, with its credential and timeouts. Failures are
/// swallowed so telemetry never blocks a payment. A batch that did not arrive is kept for the next flush, except
/// one the service refused as too large, which is discarded.
package actor TelemetryEndpointTransport: TelemetryTransport {
    package static let defaultPath = "/api/v2/telemetry/sdk"

    private let transport: any PayabliTransport
    private let path: String
    private let deviceFacts: TelemetryDeviceFacts
    private let logger: PayabliLogger

    /// A batch goes out only on a token already held, so a flush never calls the token provider. A 401 is
    /// a refusal of the caller and returns as it arrived: no refresh, no replay, nothing for the device
    /// setup to renew. A finished session refuses the batch before it is sent.
    ///
    /// - Parameter transport: the session's transport, so a batch takes the same path as every other route.
    /// - Parameter path: the route the batch is posted to.
    /// - Parameter deviceFacts: the device facts each event carries.
    package init(
        transport: any PayabliTransport,
        path: String = TelemetryEndpointTransport.defaultPath,
        deviceFacts: TelemetryDeviceFacts = .current()
    ) {
        self.init(
            transport: transport,
            path: path,
            deviceFacts: deviceFacts,
            logger: PayabliLogger(category: .telemetry)
        )
    }

    init(
        transport: any PayabliTransport,
        path: String = TelemetryEndpointTransport.defaultPath,
        deviceFacts: TelemetryDeviceFacts,
        logger: PayabliLogger
    ) {
        self.transport = transport
        self.path = path
        self.deviceFacts = deviceFacts
        self.logger = logger
    }

    @discardableResult
    package func send(_ batch: [TelemetryEvent]) async -> TelemetrySendOutcome {
        guard let entry = batch.first?.entry else { return .delivered }
        let body = TelemetryBatchBody(
            entry: entry,
            events: batch.map { TelemetryEventBody($0, facts: deviceFacts) }
        )
        do {
            let response = try await transport.perform(
                PayabliRequest.json(
                    method: .post,
                    path: path,
                    jsonBody: body,
                    isCallerRefusal: { $0.statusCode == 401 },
                    requiresHeldCredential: true
                )
            )
            guard (200 ..< 300).contains(response.statusCode) else {
                logger.warning("telemetry_batch_refused status=\(response.statusCode)")
                // A 413 alone discards: the same body is refused the same way every time. Every other
                // refusal is about the caller or the transport, so the batch is kept for the next flush.
                return response.statusCode == 413 ? .discarded : .kept
            }
            return .delivered
        } catch let refusal as PayabliGenericError where refusal.type == .missingToken {
            // Every flush lands here until host work mints a token, so it is not a failure.
            logger.debug("telemetry_batch_waiting: no token ready; the batch waits for the next flush")
            return .kept
        } catch {
            logger.warning("Telemetry batch send failed (best-effort)")
            return .kept
        }
    }
}

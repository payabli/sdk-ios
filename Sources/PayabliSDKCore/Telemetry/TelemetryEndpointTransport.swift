import Foundation

/// Best-effort transport posting telemetry batches through the SDK's own request path, with the same
/// credential and timeouts as every other route. Failures are swallowed so telemetry never blocks or
/// degrades a payment, and a batch that did not arrive is dropped, never retried.
package actor TelemetryEndpointTransport: TelemetryTransport {
    package static let defaultPath = "/api/v2/telemetry/sdk"

    private let transport: any PayabliTransport
    private let path: String
    private let deviceFacts: TelemetryDeviceFacts
    private let logger: PayabliLogger

    /// Every batch pins its credential, so a telemetry 401 neither spends the session's refresh nor replays
    /// the batch, and a finished session refuses it before it is sent.
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

    package func send(_ batch: [TelemetryEvent]) async {
        guard let entry = batch.first?.entry else { return }
        let body = TelemetryBatchBody(
            entry: entry,
            events: batch.map { TelemetryEventBody($0, facts: deviceFacts) }
        )
        do {
            let response = try await transport.perform(
                PayabliRequest.json(method: .post, path: path, jsonBody: body, pinsCredential: true)
            )
            if !(200 ..< 300).contains(response.statusCode) {
                logger.warning("telemetry_batch_refused status=\(response.statusCode)")
            }
        } catch {
            // Best-effort: a failed send is swallowed.
            logger.warning("Telemetry batch send failed (best-effort)")
        }
    }
}

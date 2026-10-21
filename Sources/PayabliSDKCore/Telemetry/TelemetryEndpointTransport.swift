import Foundation

/// Best-effort transport posting telemetry batches through the SDK's own request path, with the same
/// credential and timeouts as every other route. Failures are swallowed so telemetry never blocks or
/// degrades a payment, and a batch that did not arrive is dropped, never retried.
package actor TelemetryEndpointTransport: TelemetryTransport {
    package static let defaultPath = "/api/v2/telemetry/sdk"

    private let transport: PayabliService
    private let path: String
    private let deviceFacts: TelemetryDeviceFacts
    private let logger: PayabliLogger

    /// Takes the service rather than any transport, so the recovery layer cannot be wrapped around it.
    /// A telemetry 401 would otherwise spend the session's refresh and replay the batch, which is the
    /// opposite of the contract above.
    ///
    /// - Parameter transport: the service to post through, taken bare so the recovery layer cannot wrap it.
    /// - Parameter path: the route the batch is posted to.
    /// - Parameter deviceFacts: the device facts each event carries.
    package init(
        transport: PayabliService,
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
        transport: PayabliService,
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
    package func send(_ batch: [TelemetryEvent], droppedSinceLastSend: Int) async -> Bool {
        guard let entry = batch.first?.entry else { return true }
        let body = TelemetryBatchBody(
            entry: entry,
            events: batch.map { TelemetryEventBody($0, facts: deviceFacts) },
            droppedSinceLastSend: droppedSinceLastSend
        )
        do {
            let response = try await transport.perform(
                PayabliRequest.json(method: .post, path: path, jsonBody: body)
            )
            guard (200 ..< 300).contains(response.statusCode) else {
                logger.warning("telemetry_batch_refused status=\(response.statusCode)")
                return false
            }
            return true
        } catch {
            logger.warning("Telemetry batch send failed (best-effort)")
            return false
        }
    }
}

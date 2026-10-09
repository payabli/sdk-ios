import Foundation

/// Best-effort transport posting telemetry batches through the SDK's own request path, with the same
/// credential and timeouts as every other route. Failures are swallowed so telemetry never blocks or
/// degrades a payment; nothing is retried, and the next batch goes on the next flush tick.
package actor TelemetryEndpointTransport: TelemetryTransport {
    package static let defaultPath = "/api/v2/telemetry/sdk"

    private let transport: PayabliService
    private let path: String
    private let logger = PayabliLogger(category: .telemetry)

    /// Takes the service rather than any transport, so the recovery layer cannot be wrapped around it.
    /// A telemetry 401 would otherwise spend the session's refresh and replay the batch, which is the
    /// opposite of the contract above.
    package init(
        transport: PayabliService,
        path: String = TelemetryEndpointTransport.defaultPath
    ) {
        self.transport = transport
        self.path = path
    }

    package func send(_ batch: [TelemetryEvent]) async {
        guard !batch.isEmpty else { return }
        do {
            // The status is not read: the next tick carries the next batch either way.
            _ = try await transport.perform(
                PayabliRequest.json(method: .post, path: path, jsonBody: batch)
            )
        } catch {
            // NFR-19: best-effort — swallow.
            logger.warning("Telemetry batch send failed (best-effort)")
        }
    }
}

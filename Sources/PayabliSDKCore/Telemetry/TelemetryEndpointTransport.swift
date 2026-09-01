import Foundation

/// Best-effort transport that posts telemetry batches to the Payabli telemetry endpoint
/// (PRD §24.1, NFR-17, NFR-19).
///
/// Sends through the SDK's own request path, so a batch carries the credential and the same timeouts
/// as every other route.
///
/// Failures are swallowed — telemetry never blocks or degrades a payment. It does not retry; the next
/// batch is attempted on the next flush tick (§24.2).
public actor TelemetryEndpointTransport: TelemetryTransport {
    public static let defaultPath = "/api/v2/telemetry/sdk"

    private let transport: any PayabliTransport
    private let path: String
    private let logger = PayabliLogger(category: .telemetry)

    public init(
        transport: any PayabliTransport,
        path: String = TelemetryEndpointTransport.defaultPath
    ) {
        self.transport = transport
        self.path = path
    }

    public func send(_ batch: [TelemetryEvent]) async {
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

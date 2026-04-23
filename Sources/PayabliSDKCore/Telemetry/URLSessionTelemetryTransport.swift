import Foundation

/// Best-effort transport that POSTs telemetry batches to the Payabli backend
/// at `/api/v2/telemetry/sdk` (PRD §24.1, NFR-17, NFR-19).
///
/// Failures are swallowed — telemetry must never block or degrade payment
/// operations. The transport does not retry; the next batch will be attempted
/// on the next flush tick (§24.2).
public actor URLSessionTelemetryTransport: TelemetryTransport {
    public static let defaultPath = "/api/v2/telemetry/sdk"

    private let endpoint: URL
    private let session: URLSession
    private let logger = PayabliLogger(category: .telemetry)

    public init(environment: PayabliEnvironment, session: URLSession = .shared) {
        self.endpoint = environment.baseURL.appendingPathComponent(Self.defaultPath)
        self.session = session
    }

    public init(endpoint: URL, session: URLSession = .shared) {
        self.endpoint = endpoint
        self.session = session
    }

    public func send(_ batch: [TelemetryEvent]) async {
        guard !batch.isEmpty else { return }
        do {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            request.httpBody = try encoder.encode(batch)
            _ = try await session.data(for: request)
        } catch {
            // NFR-19: best-effort — swallow.
            logger.warning("Telemetry batch send failed (best-effort)")
        }
    }
}

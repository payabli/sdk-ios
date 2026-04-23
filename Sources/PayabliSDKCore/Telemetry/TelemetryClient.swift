import Foundation
import CryptoKit

/// Transport abstraction — production uses `URLSession` to POST to the Payabli
/// telemetry endpoint; tests inject an in-memory sink.
public protocol TelemetryTransport: Sendable {
    func send(_ batch: [TelemetryEvent]) async
}

/// In-memory transport that records batches. Useful for tests + as a default
/// when the host app has `telemetryEnabled = false`.
public actor InMemoryTelemetryTransport: TelemetryTransport {
    public private(set) var batches: [[TelemetryEvent]] = []

    public init() {}

    public func send(_ batch: [TelemetryEvent]) async {
        batches.append(batch)
    }

    public func drainBatches() -> [[TelemetryEvent]] {
        let snapshot = batches
        batches.removeAll()
        return snapshot
    }
}

/// Batched, best-effort, opt-out telemetry client (PRD §24).
///
/// - **Opt-out:** disabled when `PayabliConfig.telemetryEnabled == false` (NFR-18).
/// - **Best-effort:** transport failures never propagate to callers (NFR-19).
/// - **Batched:** flushes every 30s or when 20 events accumulate (NFR-21).
/// - **Zero PII:** caller is responsible for not passing PAN/CVV/tokens (NFR-20).
public actor TelemetryClient {
    public struct Configuration: Sendable {
        public let flushInterval: TimeInterval
        public let batchSize: Int
        public let enabled: Bool
        public let sdkVersion: String
        public let entry: String
        public let environment: String

        public init(
            flushInterval: TimeInterval = 30,
            batchSize: Int = 20,
            enabled: Bool = true,
            sdkVersion: String = "1.0.0",
            entry: String,
            environment: String
        ) {
            self.flushInterval = flushInterval
            self.batchSize = batchSize
            self.enabled = enabled
            self.sdkVersion = sdkVersion
            self.entry = entry
            self.environment = environment
        }
    }

    public let configuration: Configuration
    public let sessionId: String

    private let transport: TelemetryTransport
    private var buffer: [TelemetryEvent] = []
    private var deviceIdHash: String?

    public init(
        configuration: Configuration,
        transport: TelemetryTransport,
        sessionId: String = UUID().uuidString
    ) {
        self.configuration = configuration
        self.transport = transport
        self.sessionId = sessionId
    }

    /// Hash a raw device identifier (SHA-256) before storing. Never log the raw
    /// value (NFR-20).
    public func setDeviceId(_ rawId: String) {
        let digest = SHA256.hash(data: Data(rawId.utf8))
        deviceIdHash = digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Enqueue an event. No-op when telemetry is disabled.
    public func emit(_ name: String, properties: [String: String] = [:]) async {
        guard configuration.enabled else { return }
        let event = TelemetryEvent(
            sdkVersion: configuration.sdkVersion,
            sessionId: sessionId,
            deviceIdHash: deviceIdHash,
            entry: configuration.entry,
            environment: configuration.environment,
            event: name,
            properties: properties
        )
        buffer.append(event)
        if buffer.count >= configuration.batchSize {
            await flush()
        }
    }

    /// Immediately flush the current buffer (called on timer expiry).
    public func flush() async {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer.removeAll()
        await transport.send(batch)
    }

    public var bufferedCount: Int { buffer.count }
}

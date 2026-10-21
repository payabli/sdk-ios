import CryptoKit
import Foundation

/// Transport abstraction — production uses `URLSession` to POST to the Payabli
/// telemetry endpoint; tests inject an in-memory sink.
package protocol TelemetryTransport: Sendable {
    func send(_ batch: [TelemetryEvent]) async
}

/// Batched, best-effort telemetry client.
///
/// - **Best-effort:** transport failures never propagate to callers.
/// - **Zero PII:** caller is responsible for not passing PAN/CVV/tokens.
package actor TelemetryClient {
    package struct Configuration: Sendable {
        package let flushInterval: TimeInterval
        package let batchSize: Int
        package let sdkVersion: String
        package let entry: String
        package let environment: String

        package init(
            flushInterval: TimeInterval = 30,
            batchSize: Int = 20,
            sdkVersion: String = PayabliCore.version,
            entry: String,
            environment: String
        ) {
            self.flushInterval = flushInterval
            self.batchSize = batchSize
            self.sdkVersion = sdkVersion
            self.entry = entry
            self.environment = environment
        }
    }

    package let configuration: Configuration
    package let sessionId: String

    private let transport: TelemetryTransport
    private var buffer: [TelemetryEvent] = []
    private var deviceIdHash: String?

    package init(
        configuration: Configuration,
        transport: TelemetryTransport,
        sessionId: String = UUID().uuidString
    ) {
        self.configuration = configuration
        self.transport = transport
        self.sessionId = sessionId
    }

    /// Hash a raw device identifier (SHA-256) before storing. Never log the raw value.
    ///
    /// - Parameter rawId: the raw device identifier, hashed (SHA-256) before anything is stored.
    package func setDeviceId(_ rawId: String) {
        let digest = SHA256.hash(data: Data(rawId.utf8))
        deviceIdHash = digest.map { String(format: "%02x", $0) }.joined()
    }

    /// Enqueue an event. No-op when telemetry is disabled.
    ///
    /// - Parameter name: the event's catalog name.
    /// - Parameter properties: the string values the event carries, sent on as given.
    package func emit(_ name: String, properties: [String: String] = [:]) async {
        await emit(name, properties: properties, occurredAt: Date())
    }

    /// Enqueue an event stamped with when it happened.
    ///
    /// - Parameter name: the event's catalog name.
    /// - Parameter properties: the string values the event carries, sent on as given.
    /// - Parameter occurredAt: when the reported thing happened.
    package func emit(_ name: String, properties: [String: String] = [:], occurredAt: Date) async {
        let event = TelemetryEvent(
            sdkVersion: configuration.sdkVersion,
            sessionId: sessionId,
            deviceIdHash: deviceIdHash,
            entry: configuration.entry,
            environment: configuration.environment,
            event: name,
            properties: properties,
            timestamp: occurredAt
        )
        buffer.append(event)
        if buffer.count >= configuration.batchSize {
            await flush()
        }
    }

    /// Immediately flush the current buffer (called on timer expiry).
    package func flush() async {
        guard !buffer.isEmpty else { return }
        let batch = buffer
        buffer.removeAll()
        await transport.send(batch)
    }

    package var bufferedCount: Int {
        buffer.count
    }
}

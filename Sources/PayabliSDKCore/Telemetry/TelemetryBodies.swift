import Foundation

/// The body the telemetry route reads: the batch's entry point, its events, and what the queue evicted.
package struct TelemetryBatchBody: Encodable, Sendable {
    package let entry: String
    package let events: [TelemetryEventBody]
    package let droppedSinceLastSend: Int?

    /// - Parameter entry: the entry point every event in the batch was reported under.
    /// - Parameter events: the events, each already carrying the device facts.
    /// - Parameter droppedSinceLastSend: the eviction count, left out of the JSON when nothing was evicted.
    package init(entry: String, events: [TelemetryEventBody], droppedSinceLastSend: Int) {
        self.entry = entry
        self.events = events
        self.droppedSinceLastSend = droppedSinceLastSend > 0 ? droppedSinceLastSend : nil
    }
}

/// One event as it goes on the wire. A `nil` member is left out of the JSON.
package struct TelemetryEventBody: Encodable, Sendable {
    /// The route compares the schema version as a string.
    package static let schemaVersion = "1"

    package let schemaVersion: String
    package let sdkVersion: String
    package let timestamp: String
    package let sessionId: String
    package let entry: String
    package let environment: String
    package let event: String
    package let properties: [String: String]
    package let deviceIdHash: String?
    package let deviceType: String?
    package let deviceOs: String?
    package let osVersion: String?
    package let modelName: String?
    package let packageName: String?

    /// - Parameter event: the event as the client recorded it.
    /// - Parameter facts: the device facts added beneath every event.
    package init(_ event: TelemetryEvent, facts: TelemetryDeviceFacts) {
        schemaVersion = Self.schemaVersion
        sdkVersion = event.sdkVersion
        timestamp = Self.timestamp(event.timestamp)
        sessionId = event.sessionId
        entry = event.entry
        environment = event.environment
        self.event = event.event
        properties = event.properties
        deviceIdHash = event.deviceIdHash.flatMap { $0.isEmpty ? nil : $0 }
        deviceType = facts.deviceType
        deviceOs = facts.deviceOs
        osVersion = facts.osVersion
        modelName = facts.modelName
        packageName = facts.packageName
    }

    /// UTC with three fraction digits and a literal `Z`; the route refuses an offset.
    ///
    /// - Parameter date: the moment the event was recorded.
    /// - Returns: the timestamp as the route parses it.
    package static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }
}

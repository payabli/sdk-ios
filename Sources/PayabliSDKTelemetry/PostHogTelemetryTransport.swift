import Foundation
import PayabliSDKCore

/// Bridge protocol the host app implements against its own `PostHogSDK`
/// instance to receive SDK telemetry events.
///
/// Same motivation as `PayabliSentryBridge` — keeps `posthog-ios` out of the
/// SDK's SPM graph (NFR-26). The host app constructs a `PostHogSDK` with
/// `sessionReplay = false` (NFR-24) and forwards capture calls into it.
///
/// ```swift
/// struct HostPostHogBridge: PayabliPostHogBridge {
///     let posthog: PostHogSDK
///     func capture(_ event: String, distinctId: String, properties: [String: Any]) {
///         posthog.capture(event, distinctId: distinctId, properties: properties)
///     }
///     func flush() { posthog.flush() }
/// }
/// ```
public protocol PayabliPostHogBridge: Sendable {
    func capture(_ event: String, distinctId: String, properties: [String: Any])
    func flush()
}

public final class PostHogTelemetryTransport: TelemetryTransport, @unchecked Sendable {
    private let bridge: PayabliPostHogBridge

    public init(bridge: PayabliPostHogBridge) {
        self.bridge = bridge
    }

    public func send(_ batch: [TelemetryEvent]) async {
        for event in batch {
            var props = event.properties
            props["sdk_version"] = event.sdkVersion
            props["environment"] = event.environment
            props["session_id"] = event.sessionId
            bridge.capture(event.event, distinctId: event.entry, properties: props)
        }
        bridge.flush()
    }
}

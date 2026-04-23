import Foundation
import PayabliSDKCore

/// Bridge protocol the host app implements against its own Sentry `SentryHub`
/// to receive breadcrumbs + captured events from the SDK.
///
/// This indirection keeps `sentry-cocoa` out of the SDK's SPM graph (PRD
/// NFR-8, NFR-26). The host app that wants SDK telemetry in Sentry creates a
/// separate `SentryHub` (per NFR-22) and routes calls from this bridge into it.
///
/// Example host adapter (host app has `import Sentry`):
///
/// ```swift
/// struct HostSentryBridge: PayabliSentryBridge {
///     let hub: SentryHub
///     func addBreadcrumb(_ category: String, data: [String: Any]) {
///         let crumb = Breadcrumb(level: .info, category: category)
///         crumb.data = data
///         hub.scope.addBreadcrumb(crumb)
///     }
///     func captureError(_ message: String, tags: [String: String], extra: [String: Any]) {
///         let event = Event(level: .error)
///         event.message = SentryMessage(formatted: message)
///         event.tags = tags
///         event.extra = extra
///         hub.capture(event: event)
///     }
/// }
/// ```
public protocol PayabliSentryBridge: Sendable {
    func addBreadcrumb(_ category: String, data: [String: Any])
    func captureError(_ message: String, tags: [String: String], extra: [String: Any])
}

/// Routes telemetry events to a host-supplied Sentry bridge.
/// Failures are swallowed (NFR-19).
public final class SentryTelemetryTransport: TelemetryTransport, @unchecked Sendable {
    private let bridge: PayabliSentryBridge

    public init(bridge: PayabliSentryBridge) {
        self.bridge = bridge
    }

    public func send(_ batch: [TelemetryEvent]) async {
        for event in batch {
            if event.event.hasSuffix(".failed") {
                bridge.captureError(
                    event.event,
                    tags: [
                        "sdk_version": event.sdkVersion,
                        "entry": event.entry,
                        "environment": event.environment
                    ],
                    extra: event.properties
                )
            } else {
                bridge.addBreadcrumb(event.event, data: event.properties)
            }
        }
    }
}

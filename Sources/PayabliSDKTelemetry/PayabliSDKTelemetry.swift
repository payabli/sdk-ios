import Foundation
import PayabliSDKCore

/// Telemetry transports, carried by every SDK product.
///
/// Provides production-grade transports for `TelemetryClient`:
/// - `SentryTelemetryTransport` — forwards batched events to a **separate**
///   Sentry hub so it doesn't clash with the host app's own Sentry integration.
/// - `PostHogTelemetryTransport` — product analytics; session recording is
///   permanently disabled.
///
/// The SDK has no dependency on `sentry-cocoa` or `posthog-ios`: the host app supplies its own
/// Sentry and PostHog instances to these transports.
public enum PayabliSDKTelemetry {
    public static var version: String {
        PayabliCore.version
    }
}

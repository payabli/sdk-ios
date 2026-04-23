import Foundation
import PayabliSDKCore

/// Optional telemetry module (PRD §24.4, §24.6, NFR-26).
///
/// Provides production-grade transports for `TelemetryClient`:
/// - `URLSessionTelemetryTransport` — POSTs batches to `/api/v2/telemetry/sdk`.
/// - `SentryTelemetryTransport` — mirrors batched events to a **separate**
///   Sentry hub so it doesn't clash with the host app's own Sentry integration.
/// - `PostHogTelemetryTransport` — product analytics; session recording is
///   permanently disabled (NFR-24).
///
/// The core module intentionally has no dependency on `sentry-cocoa` or
/// `posthog-ios` (NFR-26). They live here, behind an optional SPM product
/// and CocoaPods subspec.
public enum PayabliSDKTelemetry {
    public static let version = "1.0.0"
}

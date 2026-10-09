import Foundation
import PayabliSDKCore

/// Optional telemetry module.
///
/// Provides production-grade transports for `TelemetryClient`:
/// - `SentryTelemetryTransport` — forwards batched events to a **separate**
///   Sentry hub so it doesn't clash with the host app's own Sentry integration.
/// - `PostHogTelemetryTransport` — product analytics; session recording is
///   permanently disabled.
///
/// The core module has no dependency on `sentry-cocoa` or
/// `posthog-ios`. They live here, behind an optional SPM product
/// and CocoaPods subspec.
public enum PayabliSDKTelemetry {
    public static var version: String {
        PayabliCore.version
    }
}

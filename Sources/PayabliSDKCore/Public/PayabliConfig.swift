import Foundation

/// Shared configuration for all PayabliSDK components.
///
/// Passed to each component's `configure(config:)` entry point. One
/// `PayabliConfig` can be reused across components — they share the underlying
/// auth session (PRD §28.8).
///
/// ## Authentication model
///
/// The SDK receives a short-lived access token that was **minted by the
/// partner's own server** against Payabli's token endpoint. The partner's
/// `clientSecret` never leaves the partner's backend — it is NOT embedded in
/// the mobile app binary (which would expose it to anyone who downloads the
/// app and reverse-engineers it).
///
/// The host app is responsible for:
/// 1. Calling its own backend to obtain an initial `accessToken` and passing
///    it to the SDK via `PayabliConfig.accessToken`.
/// 2. Providing an optional `tokenProvider` closure that the SDK calls when
///    the token expires or is rejected (HTTP 401). The closure asks the
///    partner backend for a fresh token.
///
/// If no `tokenProvider` is supplied, the SDK will return a `.tokenExpired`
/// error on expiry rather than attempting to refresh silently.
///
/// ## Security notes (PRD NFR-5A..C)
///
/// - The SDK never logs, never persists, and never transmits the access token
///   anywhere other than as the `Authorization: Bearer <token>` HTTP header.
/// - The token is held in memory for the duration of the session only.
/// - The `clientSecret` is not part of this config — by design, it lives on
///   the partner's server.
public struct PayabliConfig: Sendable {
    /// Pre-minted access token obtained by the host app from its own backend,
    /// which performed the client-credentials exchange server-side against
    /// `POST /api/v2/token/serverside`.
    public let accessToken: String

    /// Optional refresh callback. When the SDK detects an expired or rejected
    /// token (HTTP 401), it calls this closure to fetch a new one from the
    /// partner's backend. If `nil`, the SDK surfaces a `.tokenExpired` error.
    public let tokenProvider: PayabliTokenRefresh?

    /// Partner integration point — the platform's `entryName` concept.
    /// See PRD §5.3 FR-6A.7.
    public let entryPoint: String

    /// API environment. Determines all base URLs.
    public let environment: PayabliEnvironment

    /// Whether to emit telemetry events. Defaults to `true` (opt-out per NFR-18).
    public let telemetryEnabled: Bool

    public init(
        accessToken: String,
        tokenProvider: PayabliTokenRefresh? = nil,
        entryPoint: String,
        environment: PayabliEnvironment,
        telemetryEnabled: Bool = true
    ) {
        self.accessToken = accessToken
        self.tokenProvider = tokenProvider
        self.entryPoint = entryPoint
        self.environment = environment
        self.telemetryEnabled = telemetryEnabled
    }
}

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
/// The host app supplies one thing: a `tokenProvider` closure that asks its own backend for a
/// token. The SDK calls it when it needs one, which is before the first request and again
/// whenever a token is rejected, and holds the result in memory until then.
///
/// There is no initial token to hand over. A provider that can mint on a rejection can mint on
/// the first request, so a second way to supply the same value would only be a second thing to
/// keep correct.
///
/// ## Security notes (PRD NFR-5A..C)
///
/// - The SDK never logs, never persists, and never transmits the access token
///   anywhere other than as the `Authorization: Bearer <token>` HTTP header.
/// - The token is held in memory for the duration of the session only.
/// - The `clientSecret` is not part of this config — by design, it lives on
///   the partner's server.
public struct PayabliConfig: Sendable {
    /// Asks the host's backend for an access token, which it minted against
    /// `POST /api/v2/token/serverside` with a `clientSecret` that stays on that backend.
    ///
    /// Called before the first request and again after a rejection. Readable only inside the
    /// SDK, so a holder of this config cannot re-invoke the host's own provider.
    let tokenProvider: PayabliTokenRefresh

    /// Partner integration point — the platform's `entryName` concept.
    /// See PRD §5.3 FR-6A.7.
    public let entryPoint: String

    /// API environment. Determines all base URLs.
    public let environment: PayabliEnvironment

    /// Whether to emit telemetry events. Defaults to `true` (opt-out per NFR-18).
    public let telemetryEnabled: Bool

    /// Throws `PayabliGenericError(.invalidConfiguration)` when the entry point is empty.
    ///
    /// It throws rather than trapping because an entry point can arrive from a remote
    /// configuration at run time, and trapping would crash a payment app over one.
    ///
    /// Nothing about the token is checked here, because no token is supplied here. What the
    /// provider returns is checked where it is installed, on the first call and on every one
    /// after, so no token reaches `Authorization` unchecked.
    public init(
        entryPoint: String,
        environment: PayabliEnvironment,
        tokenProvider: @escaping PayabliTokenRefresh,
        telemetryEnabled: Bool = true
    ) throws {
        guard !entryPoint.isBlank else {
            throw PayabliGenericError(
                code: .invalidConfiguration,
                reason: "Invalid configuration",
                detail: "entryPoint is blank."
            )
        }
        self.tokenProvider = tokenProvider
        self.entryPoint = entryPoint
        self.environment = environment
        self.telemetryEnabled = telemetryEnabled
    }
}

extension PayabliConfig: CustomStringConvertible {
    /// Withholds the entry point, which names one merchant. A synthesised description prints
    /// every property, and this type reaches assertion failures and crash reports without
    /// passing the logger.
    public var description: String {
        "PayabliConfig(environment: \(environment), telemetryEnabled: \(telemetryEnabled))"
    }
}

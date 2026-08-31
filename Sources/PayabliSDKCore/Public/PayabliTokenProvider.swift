import Foundation

/// Closure that refreshes the access token by calling the partner's
/// server-side endpoint. Returns a freshly-minted token.
///
/// The SDK invokes this when its cached token is rejected (HTTP 401) or has
/// been explicitly invalidated via `PayabliAuth.invalidateToken()`.
///
/// ## Why a closure, not a hard-coded endpoint
///
/// The `clientSecret` that mints a Payabli access token MUST NOT ship in the
/// mobile binary — reverse-engineering a published app would expose it. Each
/// partner runs their own backend endpoint that holds their `clientSecret`
/// server-side and exchanges it against Payabli's token endpoint, then returns
/// the short-lived `access_token` to the app.
///
/// The host app wires this closure to call its own backend:
/// ```swift
/// try PayabliConfig(
///     accessToken: initialToken,
///     tokenProvider: { try await api.fetchPayabliAccessToken() },
///     ...
/// )
/// ```
public typealias PayabliTokenRefresh = @Sendable () async throws -> String

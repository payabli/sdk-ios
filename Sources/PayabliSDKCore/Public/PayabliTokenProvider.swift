import Foundation

/// Closure that refreshes the access token by calling the partner's
/// server-side endpoint. Returns a freshly-minted token.
///
/// The SDK invokes this when its cached token is rejected (HTTP 401).
///
/// This closure may issue its own requests through the SDK. While the refresh runs, a request made
/// on the session this closure refreshes carries the token being replaced, not the one it is about
/// to return.
///
/// The one shape that cannot work is awaiting, from inside this closure, a request issued on a
/// detached task against that same session. If that request is refused it waits for the refresh this
/// closure has yet to finish, and neither completes.
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

import Foundation

/// Closure that supplies an access token by calling the partner's server-side endpoint. Returns a
/// freshly-minted token.
///
/// It is the SDK's only source of a credential, so it is called for the first request as well as
/// after one is rejected (HTTP 401), and a host hands over no token of its own.
///
/// This closure may issue its own requests through the SDK, but not before it has returned its first
/// token. Until it does the SDK holds no credential, so such a request needs the token this closure
/// was asked to supply and is refused rather than joined, which makes a provider written that way fail
/// on first use every time.
///
/// Once a token is held, a request made on the session this closure refreshes carries the token being
/// replaced, not the one it is about to return, and that holds through a chain of sessions whose
/// providers call one another.
///
/// What this closure must not do is wait on work that itself needs this refresh to finish. Such work
/// cannot complete until the refresh does, and the refresh cannot complete until this closure
/// returns.
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
///     entryPoint: "partner-entry-point",
///     environment: .sandbox,
///     tokenProvider: { try await api.fetchPayabliAccessToken() }
/// )
/// ```
public typealias PayabliTokenRefresh = @Sendable () async throws -> String

import Foundation

/// A host token provider's own failure, tagged so it stays out of the diagnostics record.
///
/// The credential is read inside `transport.perform`, so a provider throw arrives in the same `catch`
/// as a transport failure. The diagnostics sink renders a non-SDK error with `String(describing:)` and
/// redacts only digit sequences shaped like a card number, so a provider error naming the host's own
/// backend would be recorded whole.
///
/// The host still receives its own error: each client unwraps this and rethrows `underlying`, which is
/// what the Objective-C bridge returns to an `accessTokenHandler` caller.
struct PayInProviderFailure: Error {
    let underlying: any Error
}

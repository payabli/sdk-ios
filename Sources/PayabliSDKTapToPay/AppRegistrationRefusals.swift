import Foundation
import PayabliSDKCore

/// Recognises the refusals that say the paypoint has not registered this app, on any device route.
///
/// Matched exactly on status and whole text, because one shares its opening words with assertion refusals.
enum AppRegistrationRefusals {
    /// The host error for a refusal saying the app is not registered on the paypoint.
    ///
    /// - Parameter status: the HTTP status the service refused the request with.
    /// - Parameter reason: the service's refusal text, matched exactly against its fixed words.
    /// - Returns: a `deviceSetupNotConfigured` error carrying the service's words, or `nil` for any other refusal.
    static func hostError(status: Int, reason: String) -> TapToPayError? {
        guard refusals.contains(Refusal(status: status, reason: reason)) else { return nil }
        let type = PayabliErrorType.deviceSetupNotConfigured
        return TapToPayError(type: type, reason: type.message, detail: reason)
    }

    private struct Refusal: Hashable {
        let status: Int
        let reason: String
    }

    private static let refusals: Set<Refusal> = [
        Refusal(status: 403, reason: "Application is not authorized for this paypoint."),
        Refusal(status: 403, reason: "No iOS apps are registered on the paypoint allowlist."),
        Refusal(
            status: 400,
            reason: "Assertion verification failed: Assertion rpIdHash does not match any app on the paypoint allowlist."
        )
    ]
}

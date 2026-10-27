import Foundation
import PayabliSDKCore

/// Turns a cold route's refusal into the failure a host receives, by the service's own words: each comparison is
/// exact, or a prefix where the service appends detail, and one matching nothing returns `nil`, so the status keeps
/// its own answer. `/activate` is classified by `ActivationRefusals`, and a binding that is gone is read before either.
enum ColdRouteRefusals {
    /// The refusals `/challenge` and `/register` send, which no device state decides.
    ///
    /// - Parameter code: the HTTP status, or the envelope's `resultCode`.
    /// - Parameter reason: the envelope's `resultText`, matched exactly against the service's fixed words.
    /// - Returns: the entry point's own refusal, or `nil` where the words name nothing this table knows.
    static func decline(code: Int?, reason: String) -> (any Error)? {
        guard code == 403, reason == entryPointUnusable else { return nil }
        return PayabliTTPError.entryPointRefused(reason: reason)
    }

    /// The refusals `/attest` sends: the shared ones, then the device's own.
    ///
    /// - Parameter code: the HTTP status, or the envelope's `resultCode`.
    /// - Parameter reason: the envelope's `resultText`, matched exactly against the service's fixed words, or by
    ///   prefix where the service appends detail.
    /// - Returns: the refusal's own failure, or `nil` where the words name nothing this table knows.
    static func attestDecline(code: Int?, reason: String) -> (any Error)? {
        if let shared = decline(code: code, reason: reason) {
            return shared
        }
        switch code {
        case 404 where reason == deviceNotFound,
             403 where reason == notPending:
            return PayabliTTPError.deviceSetupRequired(reason: reason)
        case 400 where reason != attestationRootUnavailable && reason.hasPrefix(verificationFailedPrefix):
            return PayabliTTPError.deviceSetupRefused(reason: reason)
        default:
            return nil
        }
    }

    private static let entryPointUnusable = "Entry point is not available for this request."
    private static let deviceNotFound = "Device not found."
    private static let notPending = "Device is not in a state that allows this operation."
    private static let verificationFailedPrefix = "Attestation verification failed: "
    /// Ruled to keep the status's own answer, so the prefix match above cannot swallow it.
    private static let attestationRootUnavailable = "Attestation verification failed: Apple attestation root is unavailable."
}

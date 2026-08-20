import Foundation
import PayabliSDKCore

/// What may be said about an error outside the call that raised it: in a log, or
/// in an event payload a host app forwards to its own telemetry.
///
/// A `PayabliError`'s `reason` and `detail` are the service's own words and can
/// quote what was submitted, so they go to the caller and to the screen and stop
/// there. Its `code` says as much as a log needs.
enum ErrorSummary {
    static func of(_ error: Error) -> String {
        switch error {
        case let ttp as PayabliTTPError:
            return of(ttp)
        case let payabli as any PayabliError:
            // `PayabliPaymentError` arrives here too, and answers the code of
            // whichever error it wraps.
            return payabli.code.rawValue
        default:
            // `NSError` on its own says nothing; the domain and code are what
            // identify a platform failure, and neither is server text.
            let ns = error as NSError
            return "\(ns.domain)(\(ns.code))"
        }
    }

    /// The case, and details that are not free text. No `reason` reaches this
    /// string.
    ///
    /// A reason cannot be classified by the case that holds it. The same
    /// `attestationFailed` carries this SDK's own words from `AppAttestService`
    /// and the service's from a decline body; `configFailed` carries a sentence
    /// written here and a `resultText` from `TTPConfigClient`; `readerSetupFailed`
    /// and `activationFailed` carry `String(describing:)` of whatever was caught.
    /// The reason still reaches the caller and the screen, on the error itself.
    ///
    /// Written out case by case rather than reflected over, because this string
    /// reaches host apps and a reflected one is whatever the compiler renders
    /// today.
    static func of(_ error: PayabliTTPError) -> String {
        switch error {
        case .notInitialized:
            return "notInitialized"
        case let .invalidState(current, attempted):
            return "invalidState(current: \(name(of: current)), attempted: \(attempted))"
        case let .notReady(current):
            return "notReady(current: \(name(of: current)))"
        case .devicePendingActivation:
            return "devicePendingActivation"
        case .tokenExpired:
            return "tokenExpired"
        case .attestationRevoked:
            return "attestationRevoked"
        case .attestationFailed:
            return "attestationFailed"
        case .configFailed:
            return "configFailed"
        case .readerSetupFailed:
            return "readerSetupFailed"
        case .nfcFailed:
            return "nfcFailed"
        case .activationFailed:
            return "activationFailed"
        case .networkError:
            return "networkError"
        case .initiateFailed:
            return "initiateFailed"
        case .updateFailed:
            return "updateFailed"
        }
    }

    /// The state is an `@objc` enum, so interpolating one renders
    /// `PayabliTTPSessionState(rawValue: 4)`. A log read at speed wants the name.
    private static func name(of state: PayabliTTPSessionState) -> String {
        switch state {
        case .idle: return "idle"
        case .attestingDevice: return "attestingDevice"
        case .fetchingConfig: return "fetchingConfig"
        case .initializingReader: return "initializingReader"
        case .ready: return "ready"
        case .sessionExpired: return "sessionExpired"
        case .reinitializing: return "reinitializing"
        case .pendingActivation: return "pendingActivation"
        case .error: return "error"
        @unknown default: return "state(\(state.rawValue))"
        }
    }
}

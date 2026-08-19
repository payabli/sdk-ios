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
        case let payment as PayabliPaymentError:
            // The umbrella carries the typed error; on its own it bridges to a
            // domain and an ordinal, which is the shape this SDK stopped showing.
            return payment.asPayabliError.code.rawValue
        case let payabli as any PayabliError:
            return payabli.code.rawValue
        default:
            // `NSError` on its own says nothing; the domain and code are what
            // identify a platform failure, and neither is server text.
            let ns = error as NSError
            return "\(ns.domain)(\(ns.code))"
        }
    }

    /// Written out case by case rather than reflected over, for two reasons.
    ///
    /// A reflected description is whatever the compiler renders today, and this
    /// string reaches host apps. And the reasons are not all the SDK's own words:
    /// `initiateFailed` and `updateFailed` carry what the service said about a
    /// charge, so they are named without one.
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
        case let .attestationRevoked(reason):
            return "attestationRevoked(\(reason))"
        case let .attestationFailed(reason):
            return "attestationFailed(\(reason))"
        case let .configFailed(reason):
            return "configFailed(\(reason))"
        case let .readerSetupFailed(reason):
            return "readerSetupFailed(\(reason))"
        case let .nfcFailed(reason):
            return "nfcFailed(\(reason))"
        case let .activationFailed(reason):
            return "activationFailed(\(reason))"
        case let .networkError(reason):
            return "networkError(\(reason))"
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

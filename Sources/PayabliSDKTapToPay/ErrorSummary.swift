import Foundation
import PayabliSDKCore

/// What may be said about an error in a log, outside the call that raised it.
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
            return of(payment)
        case let payabli as any PayabliError:
            return payabli.type.rawValue
        default:
            // `NSError` on its own says nothing; the domain and code are what
            // identify a platform failure, and neither is server text.
            let ns = error as NSError
            return "\(ns.domain)(\(ns.code))"
        }
    }

    /// A decline and a server failure both name their kind by a structured value: the decline's wire
    /// code and the server's status. Neither is free text.
    ///
    /// The server's status is read from the response before the body, which is not the authority on what was answered.
    ///
    /// - Parameter error: the payment error to name for a log.
    /// - Returns: the error's kind, with its wire code or status where it carries one.
    static func of(_ error: PayabliPaymentError) -> String {
        switch error {
        case let .decline(decline):
            return "decline(\(decline.rawCode ?? "no code"))"
        case let .server(server):
            let status = server.httpStatus ?? server.status
            return "server(\(status.map(String.init) ?? "no status"))"
        case let .validation(validation):
            return validation.type.rawValue
        case let .generic(generic):
            return generic.type.rawValue
        }
    }

    // swiftlint:disable cyclomatic_complexity

    /// The case, and details that are not free text. No `reason` reaches this string.
    ///
    /// A reason cannot be classified by the case that holds it — the same `attestationFailed` carries this
    /// SDK's words and the service's — so the reason stays on the error the caller reads.
    ///
    /// - Parameter error: the Tap to Pay error to name for a log.
    /// - Returns: the case's name, with structured details where it carries them.
    static func of(_ error: PayabliTTPError) -> String {
        switch error {
        case .notInitialized: return "notInitialized"
        case let .invalidState(current, attempted): return "invalidState(current: \(name(of: current)), attempted: \(attempted))"
        case let .notReady(current): return "notReady(current: \(name(of: current)))"
        case .devicePendingActivation: return "devicePendingActivation"
        case .tokenExpired: return "tokenExpired"
        case .attestationRevoked: return "attestationRevoked"
        case .attestationFailed: return "attestationFailed"
        case .deviceSetupRequired: return "deviceSetupRequired"
        case .deviceSetupRefused: return "deviceSetupRefused"
        case .entryPointRefused: return "entryPointRefused"
        case .configFailed: return "configFailed"
        case .cardPresentNotEnabled: return "cardPresentNotEnabled"
        case .readerSetupFailed: return "readerSetupFailed"
        case .readerCredentialsUnusable: return "readerCredentialsUnusable"
        case .readerHardwareUnsupported: return "readerHardwareUnsupported"
        case .readerUnavailable: return "readerUnavailable"
        case .guardFailed: return "guardFailed"
        case .readerDeviceRefused: return "readerDeviceRefused"
        case .readerSessionExpired: return "readerSessionExpired"
        case .nfcFailed: return "nfcFailed"
        case .activationFailed: return "activationFailed"
        case .activationCodeMalformed: return "activationCodeMalformed"
        case .networkError: return "networkError"
        case .paymentNotOpened: return "paymentNotOpened"
        case .updateFailed: return "updateFailed"
        case .termsNotAccepted: return "termsNotAccepted"
        case .readerOSVersionNotSupported: return "readerOSVersionNotSupported"
        case .cardDeclined: return "cardDeclined"
        case .outcomeUnknown: return "outcomeUnknown"
        case .paymentNotTaken: return "paymentNotTaken"
        }
    }

    // swiftlint:enable cyclomatic_complexity

    /// A log read at speed wants the name rather than the case's description.
    ///
    /// - Parameter state: the session state being named in a log line.
    /// - Returns: the state's name, as its case declares it.
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
        case .pendingTerms: return "pendingTerms"
        case .failed: return "failed"
        case .charging: return "charging"
        }
    }
}

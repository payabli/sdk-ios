import Foundation
import PayabliSDKCore

// MARK: - Where a failure lands

extension PayabliTTPSessionState {
    /// The state a failure leaves the session in, or `nil` when it leaves the session where it was. Failures
    /// a host repairs identically land together; one whose remedy is unknown lands on
    /// ``PayabliTTPFailureReason/serviceUnavailable``, where being wrong costs a retry rather than a bug report.
    ///
    /// - Parameter error: the failure to land, as the caller caught it.
    /// - Parameter registration: the activation registration the store still holds, for failures whose remedy is a code.
    /// - Returns: the state to land on, or `nil` where the session stays.
    static func landing(for error: Error, registration: StoredRegistration) -> PayabliTTPSessionState? {
        if let refusal = error as? ActivationRefusal {
            // Most refusals are about the code, and the device still owes one.
            return refusal.movesSession ? landingByType(refusal.hostError, registration: registration) : nil
        }
        if error is PinnedTokenRefusal {
            // Renewed and run once more, so it lands only if the second run is refused too, as a plain 1002.
            return nil
        }
        if error is CancellationError {
            // A withdrawn setup is asked again, which is safe.
            return .idle
        }
        guard let ttpError = error as? PayabliTTPError else {
            return landingByType(error, registration: registration)
        }

        switch ttpError {
        case .devicePendingActivation:
            // Not a failure. The device owes an activation code and the host's
            // next move is to collect one.
            return pendingActivation(registration)

        case .termsNotAccepted:
            // Not a failure either, and it has a state of its own.
            return .pendingTerms

        case .attestationRevoked, .attestationFailed:
            // Discarding the device's identity needs a positive match, and both
            // of these name the attestation.
            return .failed(reason: .deviceSetupRequired)

        case .configFailed, .readerCredentialsUnusable:
            // Terminal: every retry gets the same answer until the paypoint's configuration is fixed.
            return .failed(reason: .configurationRejected)

        case .readerOSVersionNotSupported:
            return .failed(reason: .deviceIneligible)

        case .readerSetupFailed, .networkError, .tokenExpired:
            // A reader that would not arm, a service that could not be reached
            // and a token that expired all leave the device as it was, so a host
            // is told the same call may work later.
            return .failed(reason: .serviceUnavailable)

        case .notInitialized, .invalidState, .notReady:
            // The SDK asked for something out of order, which is this side of
            // the wire.
            return .failed(reason: .sdkInternalError)

        case .nfcFailed, .initiateFailed, .updateFailed, .activationFailed, .cardDeclined, .outcomeUnknown,
             .paymentNotTaken:
            // A tap or an activation failed and the session did not. Nothing
            // about the session changed.
            return nil
        }
    }

    /// A failure that carries a catalog type, landed by that type.
    ///
    /// - Parameter error: the failure to land, read for its catalog type.
    /// - Parameter registration: the activation registration the store still holds, for the code remedy.
    /// - Returns: the state the type lands on.
    private static func landingByType(_ error: Error, registration: StoredRegistration) -> PayabliTTPSessionState {
        guard let payabliError = error as? any PayabliError else {
            return .failed(reason: .sdkInternalError)
        }
        switch payabliError.type {
        case .permissionDenied:
            // The remedy offered is an activation code. A refusal that code does
            // not repair needs a classification this map is not given.
            return pendingActivation(registration)

        case .invalidConfiguration, .deviceSetupNotConfigured, .readerCredentialsUnusable:
            return .failed(reason: .configurationRejected)

        case .deviceKeyUnavailable:
            return .failed(reason: .deviceKeyUnavailable)

        case .deviceSetupRequired:
            return .failed(reason: .deviceSetupRequired)

        case .deviceSetupUnsupported, .deviceIdentityUnavailable:
            return .failed(reason: .deviceIneligible)

        case .entryPointRefused:
            return .failed(reason: .configurationRejected)

        case .deviceSetupUnavailable:
            return .failed(reason: .serviceUnavailable)

        case .sdkInternalError:
            return .failed(reason: .sdkInternalError)

        case .sessionNotInitialized:
            // A terminal raises it only when its session is no longer the installed one.
            return .failed(reason: .sessionEnded)

        case .decodingError, .validation:
            // Both are the two sides disagreeing about the contract. A 400 is
            // the service reading the request and refusing the body, so the
            // same bytes get the same answer and a retry is not the remedy.
            return .failed(reason: .sdkInternalError)

        default:
            // Including a burned session: 410 is specified and no route has
            // been seen producing one, so its meaning is a guess until one
            // does.
            return .failed(reason: .serviceUnavailable)
        }
    }

    private static func pendingActivation(_ registration: StoredRegistration) -> PayabliTTPSessionState {
        switch registration {
        case let .held(activationId):
            return .pendingActivation(activationId: activationId)
        case .none:
            return .failed(reason: .configurationRejected)
        case .unreadable:
            return .failed(reason: .deviceKeyUnavailable)
        }
    }
}

enum StoredRegistration: Equatable {
    case held(activationId: String)
    case none
    case unreadable
}

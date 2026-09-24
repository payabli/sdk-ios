import Foundation
import PayabliSDKCore

// MARK: - Where a failure lands

extension PayabliTTPSessionState {
    /// The state a failure leaves the session in, or `nil` when it leaves the
    /// session where it was.
    ///
    /// A landing is a remedy: two failures a host repairs identically land in
    /// one place, and one whose remedy is unknown lands on
    /// ``PayabliTTPFailureReason/serviceUnavailable``, where being wrong costs a
    /// retry rather than a bug report and a host that stops trying.
    ///
    /// The map is one map for both platforms and mirrors the sibling's, so a
    /// merchant meeting one condition is sent to the same repair on either.
    static func landing(for error: Error) -> PayabliTTPSessionState? {
        guard let ttpError = error as? PayabliTTPError else {
            return landingForTransport(error)
        }

        switch ttpError {
        case .devicePendingActivation:
            // Not a failure. The device owes an activation code and the host's
            // next move is to collect one.
            return .pendingActivation

        case .termsNotAccepted:
            // Not a failure either, and it has a state of its own.
            return .pendingTerms

        case .attestationRevoked, .attestationFailed:
            // Discarding the device's identity needs a positive match, and both
            // of these name the attestation.
            return .failed(reason: .attestationRequired)

        case .configFailed:
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

        case .nfcFailed, .initiateFailed, .updateFailed, .activationFailed, .cardDeclined, .outcomeUnknown:
            // A tap or an activation failed and the session did not. Nothing
            // about the session changed.
            return nil
        }
    }

    /// A transport failure, landed by its code.
    private static func landingForTransport(_ error: Error) -> PayabliTTPSessionState {
        guard let payabliError = error as? any PayabliError else {
            return .failed(reason: .sdkInternalError)
        }
        switch payabliError.code {
        case .permissionDenied:
            // The remedy offered is an activation code. A refusal that code does
            // not repair needs a classification this map is not given.
            return .pendingActivation

        case .invalidConfiguration:
            return .failed(reason: .configurationRejected)

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
}

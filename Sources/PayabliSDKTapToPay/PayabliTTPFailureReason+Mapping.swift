import Foundation
import PayabliSDKCore

// MARK: - What a failure lands on

extension PayabliTTPFailureReason {
    /// Where a failure lands, in terms of what a host can do about it.
    ///
    /// A landing is a remedy: two failures a host repairs identically share a
    /// member, and one whose remedy is unknown is ``sdkInternalError``, because
    /// a guess sends a host down a repair that cannot work.
    static func landing(for error: Error) -> PayabliTTPFailureReason {
        guard let ttpError = error as? PayabliTTPError else {
            return landingForTransport(error)
        }

        switch ttpError {
        case .attestationRevoked, .attestationFailed, .tokenExpired:
            // The stored identity is stale or refused, and a repair does not
            // attest, so the session is built from the top.
            return .attestationRequired

        case .configFailed:
            return .configurationRejected

        case .readerSetupFailed, .readerOSVersionNotSupported:
            // The reader could not be brought up on this handset. Whether the
            // hardware, the OS build or the vendor refused it, the host's move
            // is the same.
            return .deviceIneligible

        case .networkError:
            return .serviceUnavailable

        case .notInitialized, .invalidState, .notReady, .devicePendingActivation, .termsNotAccepted:
            // A call made out of order, or a state that has its own case and
            // never reaches a failure. Landing here says the SDK asked for
            // something it should not have.
            return .sdkInternalError

        case .nfcFailed, .initiateFailed, .updateFailed, .activationFailed:
            // A charge or an activation failing does not fail the session, so
            // these reach here only through a path that should not produce them.
            return .sdkInternalError
        }
    }

    /// A transport failure, landed by its code. Anything unrecognised lands
    /// where being wrong costs nothing.
    private static func landingForTransport(_ error: Error) -> PayabliTTPFailureReason {
        guard let payabliError = error as? any PayabliError else {
            return .sdkInternalError
        }
        switch payabliError.code {
        case .missingToken, .tokenExpired, .tokenMalformed, .invalidSignature:
            return .attestationRequired

        case .permissionDenied, .sessionBurned, .invalidConfiguration:
            return .configurationRejected

        case .serverError, .networkError, .rateLimited:
            return .serviceUnavailable

        case .decodingError, .validation, .conflict, .paymentDeclined, .userCancelled, .unknown:
            return .sdkInternalError
        }
    }
}

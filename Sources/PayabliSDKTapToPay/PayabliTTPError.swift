import Foundation
import PayabliSDKCore

/// The SDK's own card-present failures. A host never receives one: every public call hands its failure
/// over as ``TapToPayError``, through ``TapToPayErrorTranslation``.
package enum PayabliTTPError: Error, Sendable {
    case notInitialized
    case invalidState(current: PayabliTTPSessionState, attempted: String)
    case notReady(current: PayabliTTPSessionState)
    case devicePendingActivation
    case attestationRevoked(reason: String)
    case attestationFailed(reason: String)
    /// The service holds no attestation for this device, so it has to be set up again before it answers.
    case deviceSetupRequired(reason: String)
    /// The service refused the attestation this device presented, in its own words.
    case deviceSetupRefused(reason: String)
    /// The entry point refuses this request at the door, before anything about the device is weighed.
    case entryPointRefused(reason: String)
    case configFailed(reason: String)
    /// Card-present payments are not enabled for this paypoint. Carries no reason: the status alone says it.
    case cardPresentNotEnabled
    case readerSetupFailed(reason: String, paymentTransId: String? = nil)
    /// A gateway credential the reader needs is blank. Carries no field name.
    case readerCredentialsUnusable
    case nfcFailed(reason: String, paymentTransId: String? = nil)
    /// The service refused to open the payment, in its own words, before any card was asked for.
    case paymentNotOpened(reason: String)
    case updateFailed(reason: String, paymentTransId: String, capture: PayabliTTPCapture, retryAfter: TimeInterval? = nil)
    case tokenExpired
    case activationFailed(reason: String)
    /// The activation code is not the six digits the service reads. Carries no reason.
    case activationCodeMalformed
    case networkError(reason: String)
    /// The merchant has not accepted the terms their platform requires before it
    /// will take a contactless payment. The SDK does not accept on their behalf.
    case termsNotAccepted

    /// This OS build cannot take contactless payments, and nothing the app or
    /// the merchant does reaches that. The remedy is a different device or an
    /// OS upgrade, where every other reader failure is transient or environmental.
    case readerOSVersionNotSupported(paymentTransId: String? = nil, capture: PayabliTTPCapture = .notCharged)

    /// This device's hardware cannot take contactless payments, and nothing the app or the merchant does
    /// reaches that. Carries no reason.
    case readerHardwareUnsupported

    /// The card reader could not be started or kept, in its own words, for a cause that ends only this
    /// attempt or this read.
    case readerUnavailable(reason: String, paymentTransId: String? = nil, capture: PayabliTTPCapture = .notCharged)

    /// A precondition the SDK itself checks before it touches the service or the reader failed, in its
    /// own words.
    case guardFailed(reason: String, paymentTransId: String? = nil)

    /// The processor refused the device during a read, so the reader session dies with it and the device
    /// has to be armed again before it reads another card.
    case readerDeviceRefused(reason: String, paymentTransId: String? = nil, capture: PayabliTTPCapture = .notCharged)

    /// The reader session is gone, so the session has to be set up again before it reads another card. Not charged
    /// where the reader was missing before the read began; unknown where the session ended during the read.
    case readerSessionExpired(paymentTransId: String? = nil, capture: PayabliTTPCapture = .notCharged)

    /// The processor refused the card. No money moved.
    case cardDeclined(paymentTransId: String)

    /// The processor answered neither an approval nor a refusal, so the SDK cannot say whether money moved.
    case outcomeUnknown(paymentTransId: String)

    /// The processor has no record of the payment, so the card was not charged. Only the close of
    /// a failed read raises it, and only for a key this run minted.
    case paymentNotTaken(paymentTransId: String)
}

package extension PayabliTTPError {
    /// Whether this failure took money from the card.
    var capture: PayabliTTPCapture {
        switch self {
        case .nfcFailed, .outcomeUnknown:
            // Raised once the reader was asked for a card, and the processor may take the sale before it answers.
            return .unknown
        case let .updateFailed(_, _, capture, _),
             let .readerOSVersionNotSupported(_, capture),
             let .readerUnavailable(_, _, capture),
             let .readerDeviceRefused(_, _, capture),
             let .readerSessionExpired(_, capture):
            return capture
        case .notInitialized, .invalidState, .notReady, .devicePendingActivation, .attestationRevoked,
             .attestationFailed, .deviceSetupRequired, .deviceSetupRefused, .entryPointRefused, .configFailed,
             .cardPresentNotEnabled, .readerSetupFailed, .readerCredentialsUnusable, .readerHardwareUnsupported,
             .guardFailed, .paymentNotOpened, .tokenExpired, .activationFailed, .activationCodeMalformed,
             .networkError, .termsNotAccepted, .cardDeclined, .paymentNotTaken:
            return .notCharged
        }
    }

    /// The payment this failure belongs to, or `nil` when the SDK holds no identifier for one.
    var paymentTransId: String? {
        switch self {
        case let .nfcFailed(_, paymentTransId),
             let .readerSetupFailed(_, paymentTransId),
             let .readerOSVersionNotSupported(paymentTransId, _),
             let .readerUnavailable(_, paymentTransId, _),
             let .readerDeviceRefused(_, paymentTransId, _),
             let .readerSessionExpired(paymentTransId, _),
             let .guardFailed(_, paymentTransId):
            return paymentTransId
        case let .updateFailed(_, paymentTransId, _, _),
             let .cardDeclined(paymentTransId),
             let .outcomeUnknown(paymentTransId),
             let .paymentNotTaken(paymentTransId):
            return paymentTransId
        case .notInitialized, .invalidState, .notReady, .devicePendingActivation, .attestationRevoked,
             .attestationFailed, .deviceSetupRequired, .deviceSetupRefused, .entryPointRefused, .configFailed,
             .cardPresentNotEnabled, .readerCredentialsUnusable, .readerHardwareUnsupported, .paymentNotOpened,
             .tokenExpired, .activationFailed, .activationCodeMalformed, .networkError, .termsNotAccepted:
            return nil
        }
    }
}

// MARK: - PayabliTTPError description

extension PayabliTTPError: LocalizedError {
    private var localizedReason: String {
        switch self {
        case .notInitialized:
            return "PayabliTTP has not been initialized"
        case let .invalidState(current, attempted):
            return "Invalid state \(current) for \(attempted)"
        case let .notReady(current):
            return "Reader not ready (state: \(current))"
        case .devicePendingActivation:
            return "Device is pending activation"
        case .tokenExpired:
            return "Access token expired"
        case .termsNotAccepted:
            return "Contactless payment terms have not been accepted"
        case .readerCredentialsUnusable:
            return "The card reader's configuration is incomplete"
        case .readerOSVersionNotSupported:
            return "This OS version does not support contactless payments"
        case .cardDeclined:
            return "The card was refused"
        case .outcomeUnknown:
            return "The payment outcome is not known"
        case .paymentNotTaken:
            return "The processor has no record of the payment, so the card was not charged"
        case .readerHardwareUnsupported:
            return "This device cannot take contactless payments"
        case .readerSessionExpired:
            return "The card reader session expired"
        case .cardPresentNotEnabled:
            return "Card-present payments are not enabled for this paypoint"
        case .activationCodeMalformed:
            return "The activation code must be six digits"
        case let .nfcFailed(reason, _),
             let .readerSetupFailed(reason, _),
             let .readerUnavailable(reason, _, _),
             let .readerDeviceRefused(reason, _, _),
             let .guardFailed(reason, _),
             let .updateFailed(reason, _, _, _):
            return reason
        case let .attestationRevoked(reason),
             let .attestationFailed(reason),
             let .deviceSetupRequired(reason),
             let .deviceSetupRefused(reason),
             let .entryPointRefused(reason),
             let .configFailed(reason),
             let .paymentNotOpened(reason),
             let .activationFailed(reason),
             let .networkError(reason):
            return reason
        }
    }

    package var errorDescription: String? {
        localizedReason
    }
}

extension PayabliTTPError {
    /// Prefix inside a case's reason that marks a person dismissing the sheet. An adapter writes it and the
    /// public edge reads it to report `USER_CANCELLED`.
    static let cancellationReasonPrefix = "cancelled:"
}

extension Error {
    /// Bridges a public call's failure to the `NSError` its `@objc` companion completes with: a
    /// ``TapToPayError`` carries its catalog number as the code in the `"com.payabli.ttp"` domain, and
    /// a cancellation bridges as Swift does.
    ///
    /// - Returns: the bridged `NSError`: a ``TapToPayError`` carries its catalog number as the code, anything else bridges as Swift does.
    func toPayabliNSError() -> NSError {
        if let tapToPayError = self as? TapToPayError {
            return tapToPayError as NSError
        }
        return payabliNSError(domain: TapToPayError.errorDomain)
    }
}

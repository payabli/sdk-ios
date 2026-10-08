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
    case configFailed(reason: String)
    case readerSetupFailed(reason: String, paymentTransId: String? = nil)
    case nfcFailed(reason: String, paymentTransId: String? = nil)
    case initiateFailed(reason: String)
    case updateFailed(reason: String, paymentTransId: String, capture: PayabliTTPCapture, retryAfter: TimeInterval? = nil)
    case tokenExpired
    case activationFailed(reason: String)
    case networkError(reason: String)
    /// The merchant has not accepted the terms their platform requires before it
    /// will take a contactless payment. The SDK does not accept on their behalf.
    case termsNotAccepted

    /// This OS build cannot take contactless payments, and nothing the app or
    /// the merchant does reaches that. The remedy is a different device or an
    /// OS upgrade, where every other reader failure is transient or
    /// environmental.
    case readerOSVersionNotSupported(paymentTransId: String? = nil, capture: PayabliTTPCapture = .notCharged)

    /// The processor refused the card. No money moved.
    case cardDeclined(paymentTransId: String)

    /// The processor answered neither an approval nor a refusal, so the SDK cannot say whether money moved.
    case outcomeUnknown(paymentTransId: String)
}

package extension PayabliTTPError {
    /// Whether this failure took money from the card.
    var capture: PayabliTTPCapture {
        switch self {
        case .nfcFailed, .outcomeUnknown:
            // Raised once the reader was asked for a card, and the processor may take the sale before it answers.
            return .unknown
        case let .updateFailed(_, _, capture, _),
             let .readerOSVersionNotSupported(_, capture):
            return capture
        case .notInitialized, .invalidState, .notReady, .devicePendingActivation, .attestationRevoked,
             .attestationFailed, .configFailed, .readerSetupFailed, .initiateFailed, .tokenExpired,
             .activationFailed, .networkError, .termsNotAccepted, .cardDeclined:
            return .notCharged
        }
    }

    /// The payment this failure belongs to, or `nil` when the SDK holds no identifier for one.
    var paymentTransId: String? {
        switch self {
        case let .nfcFailed(_, paymentTransId),
             let .readerSetupFailed(_, paymentTransId),
             let .readerOSVersionNotSupported(paymentTransId, _):
            return paymentTransId
        case let .updateFailed(_, paymentTransId, _, _),
             let .cardDeclined(paymentTransId),
             let .outcomeUnknown(paymentTransId):
            return paymentTransId
        case .notInitialized, .invalidState, .notReady, .devicePendingActivation, .attestationRevoked,
             .attestationFailed, .configFailed, .initiateFailed, .tokenExpired, .activationFailed,
             .networkError, .termsNotAccepted:
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
        case .readerOSVersionNotSupported:
            return "This OS version does not support contactless payments"
        case .cardDeclined:
            return "The card was refused"
        case .outcomeUnknown:
            return "The payment outcome is not known"
        case let .nfcFailed(reason, _),
             let .readerSetupFailed(reason, _),
             let .updateFailed(reason, _, _, _):
            return reason
        case let .attestationRevoked(reason),
             let .attestationFailed(reason),
             let .configFailed(reason),
             let .initiateFailed(reason),
             let .activationFailed(reason),
             let .networkError(reason):
            return reason
        }
    }

    package var errorDescription: String? {
        localizedReason
    }
}

extension Error {
    /// Bridges a public call's failure to the `NSError` its `@objc` companion completes with: a
    /// ``TapToPayError`` carries its catalog number as the code in the `"com.payabli.ttp"` domain, and
    /// a cancellation bridges as Swift does.
    func toPayabliNSError() -> NSError {
        if let tapToPayError = self as? TapToPayError {
            return tapToPayError as NSError
        }
        return payabliNSError(domain: TapToPayError.errorDomain)
    }
}

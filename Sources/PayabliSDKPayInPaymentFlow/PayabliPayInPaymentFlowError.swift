import Foundation
import PayabliSDKCore

public enum PayabliPayInPaymentFlowError: PayabliError, Equatable {
    case invalidInput(String)
    case missingAccessToken
    case submissionInProgress
    case transactionFailed(PayabliPayInPaymentFlowFailure)

    /// The request may have moved money and the outcome is not known.
    ///
    /// `retryKey` is the idempotency key the attempt sent. A retry carrying it is recognised as the
    /// repeat it is rather than acting a second time, and a repeat inside the service's window is
    /// refused rather than executed. The original response is not replayed, so a caller that needs the
    /// outcome still reads the transaction back.
    ///
    /// Raised only where a key was sent, which is the money-moving routes, and only where the service's
    /// answer leaves the outcome open: a network failure, a cancellation, a 5xx, a response that could
    /// not be decoded. A decline, a refused credential and a locally refused request all arrive as
    /// themselves, because there the outcome is known and a retry is a new payment.
    case submissionInterrupted(retryKey: String, underlying: any Error)

    public var code: PayabliErrorCode {
        switch self {
        case .invalidInput, .submissionInProgress:
            return .validation
        case .missingAccessToken:
            return .missingToken
        case .transactionFailed, .submissionInterrupted:
            return .unknown
        }
    }

    public var reason: String {
        switch self {
        case let .invalidInput(message):
            return message
        case .missingAccessToken:
            return "Missing access token"
        case .submissionInProgress:
            return "A payment submission is already in progress."
        case let .transactionFailed(failure):
            return failure.reasonText
        case .submissionInterrupted:
            return "The payment may have been taken and the outcome is unknown."
        }
    }

    public var detail: String? {
        switch self {
        case .invalidInput, .missingAccessToken, .submissionInProgress:
            return nil
        case let .transactionFailed(failure):
            return failure.detailText
        case let .submissionInterrupted(_, underlying):
            // The classification, never the cause's own text: an underlying error can carry wording
            // from a response body.
            return (underlying as? any PayabliError)?.code.rawValue
        }
    }

    /// Compares what a caller branches on.
    ///
    /// `submissionInterrupted` carries the error that interrupted it, and an arbitrary `Error` is not
    /// `Equatable`, so two interruptions are equal when they carry the same key and the same
    /// classification. The cause is for a caller to read, not to match on.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        switch (lhs, rhs) {
        case let (.invalidInput(left), .invalidInput(right)):
            return left == right
        case (.missingAccessToken, .missingAccessToken),
             (.submissionInProgress, .submissionInProgress):
            return true
        case let (.transactionFailed(left), .transactionFailed(right)):
            return left == right
        case let (.submissionInterrupted(leftKey, leftCause), .submissionInterrupted(rightKey, rightCause)):
            return leftKey == rightKey
                && (leftCause as? any PayabliError)?.code == (rightCause as? any PayabliError)?.code
        default:
            return false
        }
    }
}

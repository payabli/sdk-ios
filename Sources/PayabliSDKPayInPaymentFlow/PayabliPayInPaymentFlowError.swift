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
    ///
    /// `code` is the classification to branch on. `causeType` names the failing type and carries none
    /// of its message, because that message can quote a response body or name a host's own endpoint,
    /// and an error's associated values are rendered wherever the chain is walked, a crash reporter
    /// included.
    case submissionInterrupted(retryKey: String, code: PayabliErrorCode, causeType: String)

    public var code: PayabliErrorCode {
        switch self {
        case .invalidInput, .submissionInProgress:
            return .validation
        case .missingAccessToken:
            return .missingToken
        case .transactionFailed:
            return .unknown
        case let .submissionInterrupted(_, code, _):
            return code
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
        case let .submissionInterrupted(_, _, causeType):
            return causeType
        }
    }
}

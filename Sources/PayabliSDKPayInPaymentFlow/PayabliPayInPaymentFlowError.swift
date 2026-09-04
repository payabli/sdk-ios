import Foundation
import PayabliSDKCore

/// The response-code family the service answers a refused payment with, as `isApproved` reads `A`.
private let declinedFamily = "D"

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
        case let .transactionFailed(failure):
            return Self.classification(of: failure)
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

    /// What a failure the service described amounts to.
    ///
    /// The service's own response code decides before the status does, because a money-moving route
    /// answers `200` and puts the outcome in the body. A `D` is the payment being refused; anything
    /// else there is the service reporting a problem it could not process, which leaves the outcome
    /// open where a refusal settles it. The sibling separates the two the same way and for the same
    /// reason, a caller acting on them differently.
    ///
    /// A status decides for the error envelope a non-2xx carries, which is the shape with no response
    /// code of its own. The envelope's own status is read before the transport's, because the older
    /// shape answers `200` and states the real one in the body, and taking the transport's there would
    /// read a refusal the service had already made as an outcome nobody knows.
    private static func classification(
        of failure: PayabliPayInPaymentFlowFailure
    ) -> PayabliErrorCode {
        if failure.code?.hasPrefix(declinedFamily) == true {
            return .paymentDeclined
        }
        guard let status = failure.status ?? failure.httpStatusCode else {
            return .unknown
        }
        switch status {
        case 200 ..< 300:
            return .serverError
        case 400:
            return .validation
        case 402:
            return .paymentDeclined
        case 409:
            return .conflict
        case 429:
            return .rateLimited
        case 500...:
            return .serverError
        default:
            return .unknown
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

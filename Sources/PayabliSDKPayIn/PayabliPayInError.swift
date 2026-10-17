import Foundation
import PayabliSDKCore

/// The response-code family the service answers a refused payment with, as `isApproved` reads `A`.
private let declinedFamily = "D"

public enum PayabliPayInError: PayabliError, Equatable {
    case invalidInput(String)
    case missingAccessToken
    case submissionInProgress
    case transactionFailed(PayabliPayInFailure)

    /// The request may have moved money and the outcome is not known.
    ///
    /// No key is reported. To try again, submit with `attempt` set to `.retry`: the SDK sends the key of the most
    /// recent attempt whose outcome is unknown, so the service refuses a repeat rather than taking the payment again.
    /// That protection lapses after a while, and a submission that declares nothing is a new payment.
    ///
    /// **What settles the outcome is reading the transaction back**, not repeating the submission. A refused retry
    /// reports ``PayabliErrorType/retryRefused``: the earlier attempt reached the service and is still unresolved.
    ///
    /// Raised only where a key was sent, which is the money-moving routes, and only where the answer
    /// leaves the outcome open: a network failure, a cancellation, a 5xx, a response that could not be
    /// decoded, a failure the service declared on a successful status without calling it a refusal, a
    /// repeat the service recognised, and anything this SDK could not classify at all.
    ///
    /// A recognised repeat belongs to that list even though the service answered. What it answered is
    /// that it has seen the key, and the marker behind that is written before the request is handled and
    /// is never rolled back, so the attempt the key named may have taken the payment.
    ///
    /// Everything else arrives as itself, because the outcome is known and a retry there is a new
    /// payment: a refusal, a validation failure, a refused credential, a locally refused request, and a
    /// refusal for too many requests.
    ///
    /// `type` is the classification to branch on. `causeType` names the failing type and carries none
    /// of its message, because that message can quote a response body or name a host's own endpoint,
    /// and an error's associated values are rendered wherever the chain is walked, a crash reporter
    /// included.
    ///
    /// `paymentTransId` is the transaction the answer named; pass it to ``PayabliPayIn/readTransaction(_:)``.
    /// When `paymentTransId` is `nil`, the answer named no transaction. After `voidTransaction(_:)` or
    /// `captureAuthorizedTransaction(_:)`, read back the ID you passed; after `capture(_:)` or `authorize(_:)`,
    /// find the transaction in the Payabli portal by its `orderId`.
    ///
    /// `paymentReference` names the payment after `capture(_:)` or `authorize(_:)`: the one you set, or the one the
    /// SDK made. It is `nil` after `voidTransaction(_:)` and `captureAuthorizedTransaction(_:)`.
    case submissionInterrupted(
        type: PayabliErrorType,
        causeType: String,
        paymentTransId: String?,
        paymentReference: String?
    )

    public var type: PayabliErrorType {
        switch self {
        case .invalidInput, .submissionInProgress:
            return .validation
        case .missingAccessToken:
            return .missingToken
        case let .transactionFailed(failure):
            return Self.classification(of: failure)
        case let .submissionInterrupted(type, _, _, _):
            return type
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

    /// What a described failure amounts to. A `D` response code is a refusal and decides first, since a
    /// money-moving route answers `200` with the outcome in the body; otherwise the envelope's status, then
    /// the transport's, goes to ``mapPayabliHTTPError``, the one place a status becomes a classification.
    private static func classification(
        of failure: PayabliPayInFailure
    ) -> PayabliErrorType {
        if failure.code?.hasPrefix(declinedFamily) == true {
            return .paymentDeclined
        }
        guard let status = failure.status ?? failure.httpStatusCode else {
            return .unknown
        }
        do {
            try mapPayabliHTTPError(
                response: PayabliResponse(statusCode: status, headers: [:], body: Data())
            )
            // A status that mapping reads as success, so the service answered and what it answered was
            // neither an approval nor a refusal.
            return .serverError
        } catch {
            return (error as? any PayabliError)?.type ?? .unknown
        }
    }

    public var detail: String? {
        switch self {
        case .invalidInput, .missingAccessToken, .submissionInProgress:
            return nil
        case let .transactionFailed(failure):
            return failure.detailText
        case let .submissionInterrupted(_, causeType, _, _):
            return causeType
        }
    }
}

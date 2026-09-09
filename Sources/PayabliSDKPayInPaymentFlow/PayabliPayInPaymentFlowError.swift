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
    /// No key is reported, and none is reused. This SDK mints one per submission and never hands it out,
    /// so there is nothing here for a caller to carry; it also does not decide that a later submission
    /// retries this one, because two submissions described identically are indistinguishable to it.
    ///
    /// **So resubmitting after this can take the payment a second time.** What settles the outcome is
    /// reading the transaction back, not repeating the submission: the service answers a repeat rather
    /// than replaying what it did.
    ///
    /// A caller that supplied its own key may send that same key again, and the service recognises the
    /// repeat **for two minutes only**. That clock starts when the service reads the first request, not
    /// when a caller sends it, so the window a caller can rely on is shorter than two minutes by however
    /// long the attempt took. Past it the service has forgotten the key and executes the request, taking
    /// the payment again. Past it, read the transaction back instead.
    ///
    /// Raised only where a key was sent, which is the money-moving routes, and only where the answer
    /// leaves the outcome open: a network failure, a cancellation, a 5xx, a response that could not be
    /// decoded, a failure the service declared on a successful status without calling it a refusal, and
    /// anything this SDK could not classify at all.
    ///
    /// Everything else arrives as itself, because the outcome is known and a retry there is a new
    /// payment: a refusal, a validation failure, a refused credential, a locally refused request, a
    /// refusal for too many requests, and a repeat the service recognised.
    ///
    /// `code` is the classification to branch on. `causeType` names the failing type and carries none
    /// of its message, because that message can quote a response body or name a host's own endpoint,
    /// and an error's associated values are rendered wherever the chain is walked, a crash reporter
    /// included.
    case submissionInterrupted(code: PayabliErrorCode, causeType: String)

    public var code: PayabliErrorCode {
        switch self {
        case .invalidInput, .submissionInProgress:
            return .validation
        case .missingAccessToken:
            return .missingToken
        case let .transactionFailed(failure):
            return Self.classification(of: failure)
        case let .submissionInterrupted(code, _):
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
    ///
    /// The status is put to ``mapPayabliHTTPError`` rather than classified again here. That mapping is
    /// the one place a status becomes a classification, and a second copy of it drifts: it is answering
    /// the same question, so it has to give the same answer, including for a status added to it later.
    /// The body passed is empty because only the code is wanted, and every branch of that mapping falls
    /// back to a value whose code is fixed.
    ///
    /// The sibling needs no equivalent. Its money-in client puts the response to the shared mapper
    /// before it reads the body, so a non-2xx never reaches an in-body classification there. Here the
    /// body is preferred for the merchant-facing text it carries, and that preference is what leaves a
    /// status to classify at all.
    private static func classification(
        of failure: PayabliPayInPaymentFlowFailure
    ) -> PayabliErrorCode {
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
            return (error as? any PayabliError)?.code ?? .unknown
        }
    }

    public var detail: String? {
        switch self {
        case .invalidInput, .missingAccessToken, .submissionInProgress:
            return nil
        case let .transactionFailed(failure):
            return failure.detailText
        case let .submissionInterrupted(_, causeType):
            return causeType
        }
    }
}

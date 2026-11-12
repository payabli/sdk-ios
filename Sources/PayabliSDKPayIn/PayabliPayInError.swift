import Foundation
import PayabliSDKCore

/// The response-code family the service answers a refused payment with, as `isApproved` reads `A`.
let declinedFamily = "D"

/// The codes that say the processor may have taken the payment, and the classification each reports.
private let openOutcomeCodes: [String: PayabliErrorType] = ["E9060": .unknown, "E9999": .serverError]

/// A card-not-present failure: a payment, a read-back or a stored method that did not complete.
///
/// Catch the family with `catch let error as PayabliPayInError`, or one failure by its type, for example
/// `catch let error as PayabliPayInError.Unsettled`. Every failure is one of the nested types.
public class PayabliPayInError: PayabliError, @unchecked Sendable {
    public let type: PayabliErrorType
    public let reason: String
    public let detail: String?
    public let httpStatus: Int?
    public let rawCode: String?

    init(type: PayabliErrorType, reason: String, detail: String? = nil, httpStatus: Int? = nil, rawCode: String? = nil) {
        self.type = type
        self.reason = reason
        self.detail = detail
        self.httpStatus = httpStatus
        self.rawCode = rawCode
    }

    /// A value was refused before anything was sent.
    public final class InvalidInput: PayabliPayInError, @unchecked Sendable {
        /// The request member refused, as the request names it (`paymentMethod.cardnumber`), or `nil` when no
        /// single member is at fault.
        public let field: String?

        /// - Parameter field: the request member refused, or `nil` when no single member is at fault.
        /// - Parameter reason: what is wrong with it.
        public init(field: String?, reason: String) {
            self.field = field
            super.init(type: .validation, reason: reason)
        }
    }

    /// The service answered and declined the payment or the stored method.
    public final class Refused: PayabliPayInError, @unchecked Sendable {
        public let failure: PayabliPayInFailure

        /// - Parameter failure: the refusal as the service described it.
        public init(failure: PayabliPayInFailure) {
            self.failure = failure
            super.init(
                type: .paymentDeclined,
                reason: failure.reasonText,
                detail: failure.detailText,
                httpStatus: failure.httpStatusCode,
                rawCode: failure.code
            )
        }
    }

    /// The service answered with a failure that is not a decline.
    public final class ServiceError: PayabliPayInError, @unchecked Sendable {
        public let failure: PayabliPayInFailure

        /// - Parameter failure: the failure as the service described it, whose code and status decide `type`.
        public init(failure: PayabliPayInFailure) {
            self.failure = failure
            super.init(
                type: Self.classification(of: failure),
                reason: failure.reasonText,
                detail: failure.detailText,
                httpStatus: failure.httpStatusCode,
                rawCode: failure.code
            )
        }

        /// What a described failure amounts to: a `402` whose code leaves the outcome open, then a `D` code (a
        /// money-moving route answers `200` with the outcome in the body), then the envelope's status, else the
        /// transport's, through ``mapPayabliHTTPError``, the one place a status becomes a classification.
        ///
        /// - Parameter failure: the failed attempt as the envelope read it, whose code and status decide.
        /// - Returns: the classification a caller branches on.
        static func classification(of failure: PayabliPayInFailure) -> PayabliErrorType {
            if let open = openOutcome(of: failure) {
                return open
            }
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

        /// The open outcome a declined status's code reports instead of a decline: the payment may have been taken.
        ///
        /// - Parameter failure: the failed attempt as the envelope read it.
        /// - Returns: `.unknown` or `.serverError` for a `402` whose code leaves the outcome open; otherwise nil.
        static func openOutcome(of failure: PayabliPayInFailure) -> PayabliErrorType? {
            guard failure.httpStatusCode == 402, let code = failure.code else { return nil }
            return openOutcomeCodes[code]
        }
    }

    /// The service answered with something the SDK could not read.
    public final class Undecodable: PayabliPayInError, @unchecked Sendable {
        public init() {
            super.init(type: .decodingError, reason: "The response could not be read.")
        }

        /// - Parameter reason: which answer could not be read.
        /// - Parameter httpStatus: the status the unreadable answer came with.
        package init(reason: String, httpStatus: Int?) {
            super.init(type: .decodingError, reason: reason, httpStatus: httpStatus)
        }
    }

    /// The request may have moved money and the outcome is not known.
    ///
    /// No key is reported. To try again, submit with `attempt` set to `.retry` and the same `paymentReference`: the SDK
    /// sends that payment's key, so the service refuses a repeat rather than taking the payment again. That protection
    /// lapses after a while, and a submission that declares nothing is a new payment.
    ///
    /// **What settles the outcome is reading the transaction back**, not repeating the submission. A refused retry
    /// reports ``PayabliErrorType/retryRefused``: the earlier attempt reached the service and is still unresolved.
    ///
    /// Raised when a send that may have moved money came back with nothing that says how it ended: a new
    /// payment's request reached the network and got no answer, a retry of a payment came back unanswered,
    /// or a send naming a transaction — the capture of an authorization, or a void — came back unanswered.
    /// A definite outcome, and a new payment that never left the device, arrive as themselves.
    ///
    /// `type` is the classification to branch on. `underlying` names the failing type and carries none
    /// of its message, because that message can quote a response body or name a host's own endpoint,
    /// and an error's properties are rendered wherever the chain is walked, a crash reporter included.
    /// `detail` is the failure's `reason` when it is a ``PayabliError``, which for an answer is the service's own
    /// text, and `nil` for a platform error. `httpStatus` and `rawCode` are the failure's when it was an answer.
    public final class Unsettled: PayabliPayInError, @unchecked Sendable {
        /// The failure that left the outcome unknown, redacted to its type: it carries no message.
        public var underlying: any Error {
            redactedCause
        }

        let redactedCause: RedactedCause

        /// The fields the cause blamed, read before it was redacted, so the form can mark them.
        let rejectedFields: Set<PayabliPayInField>

        /// The transaction the answer named; pass it to ``PayabliPayIn/readTransaction(_:)``. `nil` when the
        /// answer named none: after `voidTransaction(_:)` or `captureAuthorizedTransaction(_:)`, read back the ID you
        /// passed; after `capture(_:)` or `authorize(_:)`, find the transaction in the Payabli portal by its `orderId`.
        public let paymentTransId: String?

        /// The payment's name after `capture(_:)` or `authorize(_:)`: the one you set, or the one the SDK made. `nil`
        /// after `voidTransaction(_:)` and `captureAuthorizedTransaction(_:)`.
        public let paymentReference: String?

        /// - Parameter cause: the failure that left the outcome unknown, whose type, status and code this carries.
        /// - Parameter paymentTransId: the transaction the answer named, if it named one.
        /// - Parameter paymentReference: the payment's name.
        public convenience init(cause: any PayabliError, paymentTransId: String? = nil, paymentReference: String? = nil) {
            self.init(
                type: cause.type,
                cause: cause,
                paymentTransId: paymentTransId,
                paymentReference: paymentReference
            )
        }

        /// - Parameter type: the classification, which can differ from the cause's (a refused key's retry).
        /// - Parameter cause: the failure that left the outcome unknown.
        /// - Parameter paymentTransId: the transaction the answer named, if it named one.
        /// - Parameter paymentReference: the payment's name.
        package init(type: PayabliErrorType, cause: any Error, paymentTransId: String?, paymentReference: String?) {
            let answer = cause as? any PayabliError
            redactedCause = cause as? RedactedCause ?? RedactedCause(cause)
            rejectedFields = PayabliPayInRejectedFields.fields(in: cause)
            self.paymentTransId = paymentTransId
            self.paymentReference = paymentReference
            super.init(
                type: type,
                reason: "The transaction's status is unknown. Read the transaction back to see its status.",
                detail: answer?.reason,
                httpStatus: answer?.httpStatus,
                rawCode: answer?.rawCode
            )
        }

        /// - Parameter source: the open outcome as the request reported it.
        /// - Parameter type: the classification the caller receives.
        /// - Parameter paymentReference: the payment's name, which the request did not know.
        init(_ source: Unsettled, type: PayabliErrorType, paymentReference: String?) {
            redactedCause = source.redactedCause
            rejectedFields = source.rejectedFields
            paymentTransId = source.paymentTransId
            self.paymentReference = paymentReference
            super.init(
                type: type,
                reason: source.reason,
                detail: source.detail,
                httpStatus: source.httpStatus,
                rawCode: source.rawCode
            )
        }
    }

    /// A submission was made while another was in flight; nothing was sent.
    public final class AlreadySubmitting: PayabliPayInError, @unchecked Sendable {
        public init() {
            super.init(type: .validation, reason: "A payment submission is already in progress.")
        }
    }

    /// The form's submission was cancelled before it finished. A cancelled direct call throws `CancellationError`.
    public final class Interrupted: PayabliPayInError, @unchecked Sendable {
        public init() {
            super.init(type: .userCancelled, reason: "The payment was interrupted before it finished.")
        }
    }
}

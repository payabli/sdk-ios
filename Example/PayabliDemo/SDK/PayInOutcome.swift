import Foundation
import PayabliSDKCore
import PayabliSDKPayIn

/// What a submission ended as, in this app's own words, so no screen holds an SDK type it would have to follow.
/// The rows are derived here: a screen reading a result's fields one by one names the type again.
/// A success shows its code and identifiers, never the service's text.
struct PayInOutcome {
    let code: String
    let transaction: PayInTransaction?
    let storedMethod: PayInStoredMethod?

    /// The result's code and identifiers, as rows a screen renders.
    let summaryRows: [PayInSummaryRow]

    /// What a result screen leads with.
    var headline: String {
        "Code \(code)"
    }

    /// The identifier a reversal can be sent for, or nothing.
    ///
    /// Present is not the same as usable. The SDK trims the value and refuses a blank one, and
    /// refuses `.` and `..` besides, because either would name a route rather than a transaction.
    /// Offering the button for one of those gives an operator an action that can only ever come
    /// back as invalid input.
    var reversibleTransId: String? {
        guard let transId = transaction?.paymentTransId?.trimmingCharacters(in: .whitespacesAndNewlines),
              !transId.isEmpty,
              transId != ".",
              transId != ".."
        else {
            return nil
        }
        return transId
    }
}

/// One line of a result screen.
struct PayInSummaryRow: Identifiable {
    let label: String
    let value: String

    var id: String {
        label
    }
}

/// The payment behind a capture.
struct PayInTransaction {
    let paymentTransId: String?
    let gatewayTransId: String?
    let method: String?
    let operation: String?
}

/// The instrument behind a save.
struct PayInStoredMethod {
    let storedMethodId: String?
}

/// A submission that did not go through.
struct PayInFailure {
    /// The message for the failure's category, or this app's own text for a case it words itself.
    /// It never carries the error's own text, which is the service's and goes to no screen.
    let message: String

    /// The failure's code, carrying nothing from the wire, which is what the log records.
    let logLabel: String

    /// Whether the flow refused this because another submission was already running.
    ///
    /// It says nothing about the request that was made, because the request was never made. A
    /// screen that reads it as this request's answer reports a failure for something it did not do,
    /// and hides whatever the running one goes on to say.
    let refusedForAnotherSubmission: Bool

    /// Whether the request may have reached the service, leaving nobody able to say what it did.
    ///
    /// A screen offering to send it again after this offers a second one, not a retry: the SDK mints
    /// a key per call, so the service has nothing to recognise the repeat by.
    let outcomeIsUnresolved: Bool

    /// Whether the service refused this as a repeat of an attempt it already holds.
    ///
    /// That refusal lapses after a while, so submitting again later can take a second
    /// payment. What settles the earlier attempt is reading the transaction back.
    let isDuplicateSubmission: Bool

    /// Whether the service answered the payment, with a decline or a refusal of what was sent, which ends any
    /// retry of it. A refusal made on the device, or a failure the service may not have seen, leaves one open.
    let answersThePayment: Bool
}

extension PayInOutcome {
    /// The form reports a payment or a stored method as one success shape, which this app
    /// reads back as the two outcomes its screens already know.
    init(_ success: PayabliPayInFormSuccess) {
        switch success {
        case let .payment(result):
            self.init(result)
        case let .method(storedMethod):
            self.init(PayabliPayInResult(storedPaymentMethod: storedMethod))
        }
    }

    init(_ result: PayabliPayInResult) {
        code = result.code
        transaction = result.transaction.map {
            PayInTransaction(
                paymentTransId: $0.paymentTransId,
                gatewayTransId: $0.gatewayTransId,
                method: $0.method,
                operation: $0.operation
            )
        }
        storedMethod = result.storedPaymentMethod.map {
            PayInStoredMethod(storedMethodId: $0.storedMethodId)
        }
        summaryRows = Self.rows(for: result)
    }

    /// Built row by row rather than as one array of pairs mapped into rows. Thirteen
    /// heterogeneous literals and a `map` is enough for the type checker to give up
    /// on a slower machine, which it did in CI while compiling here.
    private static func rows(for result: PayabliPayInResult) -> [PayInSummaryRow] {
        let transaction = result.transaction
        var rows: [PayInSummaryRow] = []
        rows.append(PayInSummaryRow(label: "Code", value: result.code))
        if let storedMethod = result.storedPaymentMethod {
            rows.append(PayInSummaryRow(label: "Stored method ID", value: text(storedMethod.storedMethodId)))
            return rows
        }
        rows.append(PayInSummaryRow(label: "Payment trans ID", value: text(transaction?.paymentTransId)))
        rows.append(PayInSummaryRow(label: "Gateway trans ID", value: text(transaction?.gatewayTransId)))
        rows.append(PayInSummaryRow(label: "Order ID", value: text(transaction?.orderId)))
        rows.append(PayInSummaryRow(label: "Method", value: text(transaction?.method)))
        rows.append(PayInSummaryRow(label: "Operation", value: text(transaction?.operation)))
        rows.append(PayInSummaryRow(label: "Status", value: text(transaction?.transStatus.map(String.init))))
        rows.append(PayInSummaryRow(label: "Total amount", value: amount(transaction?.totalAmount)))
        rows.append(PayInSummaryRow(label: "Fee amount", value: amount(transaction?.feeAmount)))
        rows.append(PayInSummaryRow(label: "Source", value: text(transaction?.source)))
        return rows
    }

    /// A dash where the service answered nothing, so every row renders.
    private static func text(_ value: String?) -> String {
        guard let value, !value.isEmpty else { return "-" }
        return value
    }

    /// The response carries no currency, so this names one. The reader's own
    /// locale decides the grouping and the decimal mark.
    private static func amount(_ value: Double?) -> String {
        guard let value else { return "-" }
        return value.formatted(.currency(code: "USD"))
    }
}

extension PayInFailure {
    /// The refusal is about the key, and the earlier attempt's fate is the open question. Offering a
    /// fresh attempt as the next step answers it with a second payment, because the refusal lapses.
    private static let duplicateMessage =
        "Duplicate submission (409): this attempt's idempotency key has already "
            + "been used, so the service refused this request without running it. That says "
            + "nothing about the attempt the key first named, which may have taken the payment. "
            + "Read that attempt back before sending anything else: this refusal does not last, "
            + "so a further attempt can be a second payment rather than a retry of the first."

    /// What an outcome nobody knows means for a reversal.
    ///
    /// The SDK's reason names the transaction. After a reversal it is the reversal whose fate is
    /// open, so this words the open question for the operator reading it.
    private static let unknownReversalMessage =
        "The reversal may have been applied and the outcome is unknown. Read the "
            + "transaction back rather than reversing it again."

    /// A reversal refused because an earlier one on this payment reached the service. That one may still be
    /// running, so the next step is a read a little later.
    private static let reversalStillRunningMessage =
        "The earlier reversal may still be running. Read the payment again shortly."

    /// A failure reads as the message for its category, never as `localizedDescription`, which is the service's text.
    ///
    /// - Parameter operation: what the form was for. A stored method sends no idempotency key, so a conflict there
    ///   is not a duplicate and reads as the service's own answer.
    init(_ error: Error, operation: PayInOperation) {
        let duplicate = operation.canRepeatUnderOneKey && Self.isDuplicateSubmission(error)
        isDuplicateSubmission = duplicate
        outcomeIsUnresolved = Self.leavesOutcomeUnknown(error)
        refusedForAnotherSubmission = Self.refusedForAnotherSubmission(error)
        answersThePayment = Self.answersThePayment(error)
        logLabel = LoggableError.label(for: error)
        message = Self.message(for: error, operation: operation, duplicate: duplicate)
    }

    private static func message(
        for error: Error,
        operation: PayInOperation,
        duplicate: Bool
    ) -> String {
        if duplicate {
            return duplicateMessage
        }
        if operation == .void, (error as? any PayabliError)?.type == .retryRefused {
            return reversalStillRunningMessage
        }
        // A reversal's open outcome gets its own copy, so an operator reads what is open after one.
        if operation == .void, leavesOutcomeUnknown(error) {
            return unknownReversalMessage
        }
        return categoryMessage(for: category(of: error), operation: operation)
    }

    /// The category whose message a failure shows. A submission that may have gone through reads as
    /// outcome-unknown whatever its own category is.
    private static func category(of error: Error) -> PayabliErrorCategory {
        if leavesOutcomeUnknown(error) {
            return .outcomeUnknown
        }
        return (error as? any PayabliError)?.category ?? PayabliErrorType.unknown.category
    }

    /// The form's own message for each category and operation, and this app's for a reversal, which the form
    /// does not submit.
    private static func categoryMessage(for category: PayabliErrorCategory, operation: PayInOperation) -> String {
        switch (operation, category) {
        case (.capture, .declined), (.authorize, .declined):
            "The payment was declined. Try another payment method."
        case (.capture, .retryLater), (.authorize, .retryLater):
            "The payment couldn't be completed. Please try again."
        case (.capture, .outcomeUnknown), (.authorize, .outcomeUnknown):
            "This payment may have gone through. Check before paying again."
        case (.capture, _), (.authorize, _):
            "The payment couldn't be completed."
        case (.storedMethod, .declined):
            "This payment method couldn't be saved. Try another one."
        case (.storedMethod, .retryLater):
            "The payment method couldn't be saved. Please try again."
        case (.storedMethod, .outcomeUnknown):
            "We couldn't confirm the payment method was saved."
        case (.storedMethod, _):
            "The payment method couldn't be saved."
        case (.void, .retryLater):
            "The reversal couldn't be completed. Please try again."
        case (.void, _):
            "The reversal couldn't be completed."
        }
    }

    /// Only the shapes the service's own answer arrives in. A refusal made on the device can carry the same
    /// error type, so the type alone does not tell them apart.
    private static func answersThePayment(_ error: Error) -> Bool {
        switch error {
        case PayabliPaymentError.decline, PayabliPaymentError.validation:
            return true
        case is PayabliPayInError.Refused:
            return true
        case let failure as PayabliPayInError.ServiceError:
            return failure.type == .paymentDeclined || failure.type == .validation
        default:
            return false
        }
    }

    private static func refusedForAnotherSubmission(_ error: Error) -> Bool {
        error is PayabliPayInError.AlreadySubmitting
    }

    /// Whether the request may have reached the service, so sending it again is not safe to offer.
    private static func leavesOutcomeUnknown(_ error: Error) -> Bool {
        if error is PayabliPayInError.Unsettled {
            return true
        }
        // A request cancelled in flight may already have reached the service.
        return error is CancellationError
    }

    private static func isDuplicateSubmission(_ error: Error) -> Bool {
        let answered = (error as? PayabliPayInError.Refused)?.failure ?? (error as? PayabliPayInError.ServiceError)?.failure
        if answered?.httpStatusCode == 409 {
            return true
        }
        // An empty body carries no code of its own, so the status mapping supplies one. The code says
        // a conflict and no more; that a conflict here is a repeat is what the operation above adds,
        // since only an operation that sends a key can have one refused.
        if let payabliError = error as? any PayabliError, payabliError.type == .conflict {
            return true
        }
        return false
    }
}

import Foundation
import PayabliSDKCore
import PayabliSDKPayIn

/// What a submission ended as, in this app's own words.
///
/// The form calls back with the SDK's own result and error types. These are what
/// the screens are handed instead, so no view holds a type it would have to
/// follow when the SDK changes.
///
/// The rows and the response text are derived here rather than transcribed by a
/// screen: a result carries a dozen fields and an encodable response, and a
/// screen that reads them one by one names the type again.
struct PayInOutcome {
    let code: String
    let reason: String?
    let explanation: String?
    let transaction: PayInTransaction?
    let storedMethod: PayInStoredMethod?

    /// Everything the service answered, as rows a screen renders.
    let summaryRows: [PayInSummaryRow]

    /// The raw response, formatted, for the developer reading this tab.
    let responseJSON: String

    /// What a result screen leads with.
    var headline: String {
        reason ?? explanation ?? code
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
    let responseText: String
    let resultText: String?
    let resultCode: Int?
}

/// A submission that did not go through.
struct PayInFailure {
    /// Displayable, and what a screen shows.
    let message: String

    /// The failure's own classification, carrying nothing from the wire, so it is
    /// the part safe to record.
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
    /// It holds one for two minutes from the first request, so submitting again is
    /// refused the same way only inside that. Past it the same key is executed, and
    /// a new attempt is what sends a payment of its own.
    let isDuplicateSubmission: Bool
}

extension PayInOutcome {
    init(_ result: PayabliPayInResult) {
        code = result.code
        reason = result.reason
        explanation = result.explanation
        transaction = result.transaction.map {
            PayInTransaction(
                paymentTransId: $0.paymentTransId,
                gatewayTransId: $0.gatewayTransId,
                method: $0.method,
                operation: $0.operation
            )
        }
        storedMethod = result.storedPaymentMethod.map {
            PayInStoredMethod(
                storedMethodId: $0.storedMethodId,
                responseText: $0.responseText,
                resultText: $0.resultText,
                resultCode: $0.resultCode
            )
        }
        summaryRows = Self.rows(for: result)
        responseJSON = Self.json(for: result)
    }

    /// Built row by row rather than as one array of pairs mapped into rows. Thirteen
    /// heterogeneous literals and a `map` is enough for the type checker to give up
    /// on a slower machine, which it did in CI while compiling here.
    private static func rows(for result: PayabliPayInResult) -> [PayInSummaryRow] {
        let transaction = result.transaction
        var rows: [PayInSummaryRow] = []
        rows.append(PayInSummaryRow(label: "Code", value: result.code))
        rows.append(PayInSummaryRow(label: "Reason", value: text(result.reason)))
        rows.append(PayInSummaryRow(label: "Explanation", value: text(result.explanation)))
        rows.append(PayInSummaryRow(label: "Action", value: text(result.action)))
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

    private static func json(for result: PayabliPayInResult) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard
            let data = try? encoder.encode(result.apiResponse),
            let text = String(data: data, encoding: .utf8)
        else {
            return "Unable to render response JSON."
        }
        return text
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
    /// fresh attempt as the next step answers it with a second payment: the service holds the key for
    /// two minutes from the first request, and past that the same key is executed rather than refused.
    private static let duplicateMessage =
        "Duplicate submission (409): this attempt's idempotency key has already "
            + "been used, so the service refused this request without running it. That says "
            + "nothing about the attempt the key first named, which may have taken the payment. "
            + "Read that attempt back before sending anything else — past the service's "
            + "two-minute window the same key is executed, so a further attempt is a second "
            + "payment rather than a retry of the first."

    /// What an outcome nobody knows means for a reversal.
    ///
    /// The SDK words this one for a payment, which is what every other call here is. After a reversal
    /// it is the reversal whose fate is open, and reading it as the payment's sends an operator to
    /// the wrong question.
    private static let unknownReversalMessage =
        "The reversal may have been applied and the outcome is unknown. Read the "
            + "transaction back rather than reversing it again."

    /// Every failure reads as `localizedDescription`, which each SDK error type
    /// writes for a merchant: a validation failure appends the rejected fields, a
    /// decline appends the action the payer can take, and the rest fall back to the
    /// reason and its detail. Reducing them here to reason and detail dropped
    /// exactly the part worth showing.
    ///
    /// - Parameter operation: what the form was for. A stored method sends no
    ///   idempotency key and offers no new attempt, so a conflict on that flow is
    ///   not the duplicate this message describes, and it reads as the service's own
    ///   answer.
    init(_ error: Error, operation: PayInOperation) {
        let duplicate = operation.canRepeatUnderOneKey && Self.isDuplicateSubmission(error)
        isDuplicateSubmission = duplicate
        outcomeIsUnresolved = Self.leavesOutcomeUnknown(error)
        refusedForAnotherSubmission = Self.refusedForAnotherSubmission(error)
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
        // The SDK words an open outcome as the payment's, because every other call here is one.
        if operation == .void, leavesOutcomeUnknown(error) {
            return unknownReversalMessage
        }
        return error.localizedDescription
    }

    private static func refusedForAnotherSubmission(_ error: Error) -> Bool {
        if case .submissionInProgress = error as? PayabliPayInError {
            return true
        }
        return false
    }

    /// Whether the request may have reached the service, so sending it again is not safe to offer.
    private static func leavesOutcomeUnknown(_ error: Error) -> Bool {
        if case .submissionInterrupted = error as? PayabliPayInError {
            return true
        }
        return false
    }

    private static func isDuplicateSubmission(_ error: Error) -> Bool {
        if case let PayabliPayInError.transactionFailed(failure) = error,
           failure.httpStatusCode == 409
        {
            return true
        }
        // An empty body carries no code of its own, so the status mapping supplies one. The code says
        // a conflict and no more; that a conflict here is a repeat is what the operation above adds,
        // since only an operation that sends a key can have one refused.
        if let payabliError = error as? any PayabliError, payabliError.code == .conflict {
            return true
        }
        return false
    }
}

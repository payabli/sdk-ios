import Foundation
import PayabliSDKCore
import PayabliSDKPayInPaymentFlow

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

    /// Whether the service answered from an attempt that already reached it, in
    /// which case submitting again does the same thing and only a new attempt
    /// sends a payment of its own.
    let isDuplicateSubmission: Bool
}

extension PayInOutcome {
    init(_ result: PayabliPayInPaymentFlowResult) {
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
    private static func rows(for result: PayabliPayInPaymentFlowResult) -> [PayInSummaryRow] {
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

    private static func json(for result: PayabliPayInPaymentFlowResult) -> String {
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
    /// `mapPayabliHTTPError` has no 409 case, so a duplicate arrives through the
    /// default branch as the bare reason `HTTP 409`, which names a status and no
    /// cause. The typed failure carries the code where the API answered with a
    /// body; the generic error is what an empty one becomes.
    private static let bareConflictReason = "HTTP 409"

    private static let duplicateMessage =
        "Duplicate submission (409): this attempt's idempotency key has already "
            + "been used, so the service answered from the earlier one rather than taking "
            + "a payment. Submitting again does the same. Start a new attempt to send a "
            + "payment of its own."

    /// - Parameter operation: what the form was for. A stored method sends no
    ///   idempotency key and offers no new attempt, so a conflict on that flow is
    ///   not the duplicate this message describes.
    init(_ error: Error, operation: PayInOperation) {
        let duplicate = operation == .capture && Self.isDuplicateSubmission(error)
        isDuplicateSubmission = duplicate
        logLabel = LoggableError.label(for: error)
        message = duplicate ? Self.duplicateMessage : Self.describe(error)
    }

    private static func describe(_ error: Error) -> String {
        if let payabliError = error as? any PayabliError {
            if let detail = payabliError.detail, !detail.isEmpty, detail != payabliError.reason {
                return "\(payabliError.reason)\n\(detail)"
            }
            return payabliError.reason
        }
        return error.localizedDescription
    }

    private static func isDuplicateSubmission(_ error: Error) -> Bool {
        if case let PayabliPayInPaymentFlowError.transactionFailed(failure) = error,
           failure.httpStatusCode == 409
        {
            return true
        }
        // The exact string the transport builds for a status it does not map, not
        // a substring: a validation failure's reason is the server's own title,
        // which can carry those three digits for its own reasons.
        if let payabliError = error as? any PayabliError, payabliError.reason == Self.bareConflictReason {
            return true
        }
        return false
    }
}

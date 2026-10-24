import Foundation
import PayabliSDKCore

/// The message the form shows the payer for a failure it marks no field for. It is chosen by the
/// form's operation and the failure's category, and never carries the failure's own text, which
/// reaches the host only.
enum PayabliPayInFailureMessage {
    /// The message for a failed submission, in the wording the host supplied where it supplied any.
    ///
    /// - Parameters:
    ///   - error: The failure the submission threw.
    ///   - operation: What the form submitted.
    ///   - labels: The wording the form was given, whose message for the failure's category
    ///     replaces the SDK's own.
    /// - Returns: The host's message for the failure's category when it carries one, otherwise
    ///   the SDK's own message for the category ``messageCategory(for:)`` names.
    static func text(
        for error: any Error,
        operation: PayabliPayInOperation,
        labels: PayabliPayInFormLabels
    ) -> String {
        let category = messageCategory(for: error)
        return labels.failureMessage(for: category) ?? text(for: category, operation: operation)
    }

    /// The category whose message the form draws for a failure: an interrupted submission may have
    /// gone through, so it reads as outcome-unknown whatever its own category is, and a failure
    /// outside the catalog reads as the unknown outcome the form reports it to the host as.
    ///
    /// - Parameter error: The failure the submission threw.
    /// - Returns: The category that picks the message.
    static func messageCategory(for error: any Error) -> PayabliErrorCategory {
        if case .submissionInterrupted = error as? PayabliPayInError {
            return .outcomeUnknown
        }
        return (error as? any PayabliError)?.category ?? PayabliErrorType.unknown.category
    }

    /// The message for a failed submission.
    ///
    /// - Parameters:
    ///   - error: The failure the submission threw.
    ///   - operation: What the form submitted.
    /// - Returns: The unknown-outcome message for an interrupted submission, whatever its category; otherwise the
    ///   message for the error's category, with a failure outside the catalog read as outcome-unknown.
    static func text(for error: any Error, operation: PayabliPayInOperation) -> String {
        text(for: messageCategory(for: error), operation: operation)
    }

    /// The message for one category of failure.
    ///
    /// A save moves no money, so it has its own texts and none says a payment may have gone through.
    ///
    /// - Parameters:
    ///   - category: Which of the catalog's categories the failure is, which picks the message.
    ///   - operation: What the form submitted.
    /// - Returns: The message the payer sees.
    static func text(for category: PayabliErrorCategory, operation: PayabliPayInOperation) -> String {
        switch (operation, category) {
        case (.capture, .declined), (.authorize, .declined):
            "The payment was declined. Try another payment method."
        case (.capture, .retryLater), (.authorize, .retryLater):
            "The payment couldn't be completed. Please try again."
        case (.capture, .outcomeUnknown), (.authorize, .outcomeUnknown):
            "This payment may have gone through. Check before paying again."
        case (.capture, _), (.authorize, _):
            "The payment couldn't be completed."
        case (.storePaymentMethod, .declined):
            "This payment method couldn't be saved. Try another one."
        case (.storePaymentMethod, .retryLater):
            "The payment method couldn't be saved. Please try again."
        case (.storePaymentMethod, _):
            "The payment method couldn't be saved."
        }
    }
}

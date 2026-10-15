import Foundation
import PayabliSDKCore

/// The message the form shows the payer for a failure it marks no field for. It is chosen by the
/// form's operation and the failure's category, and never carries the failure's own text, which
/// reaches the host only.
enum PayabliPayInFailureMessage {
    /// The message for a failed submission.
    ///
    /// - Parameters:
    ///   - error: The failure the submission threw.
    ///   - operation: What the form submitted.
    /// - Returns: The message for the error's category, or the default message for an error outside the catalog.
    static func text(for error: any Error, operation: PayabliPayInOperation) -> String {
        text(for: (error as? any PayabliError)?.category ?? .internal, operation: operation)
    }

    /// The message for one category of failure.
    ///
    /// A save moves no money, so it has its own texts and none says a payment may have gone through.
    ///
    /// - Parameters:
    ///   - category: The failure's category.
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

import Foundation
import PayabliSDKCore

/// The message the form shows the payer for a failure it marks no field for. It is chosen by the
/// failure's category and never carries the failure's own text, which reaches the host only.
enum PayabliPayInFailureMessage {
    /// The message for a failed submission.
    ///
    /// - Parameter error: The failure the submission threw.
    /// - Returns: The message for the error's category, or the default message for an error outside the catalog.
    static func text(for error: any Error) -> String {
        guard let category = (error as? any PayabliError)?.category else { return defaultText }
        return text(for: category)
    }

    /// The message for one category of failure.
    ///
    /// - Parameter category: The failure's category.
    /// - Returns: The message the payer sees.
    static func text(for category: PayabliErrorCategory) -> String {
        switch category {
        case .declined:
            "The payment was declined. Try another payment method."
        case .retryLater:
            "The payment couldn't be completed. Please try again."
        case .outcomeUnknown:
            "This payment may have gone through. Check before paying again."
        case .credential, .configuration, .invalidRequest, .device, .internal:
            defaultText
        }
    }

    private static let defaultText = "The payment couldn't be completed."
}

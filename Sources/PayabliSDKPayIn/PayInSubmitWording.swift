import Foundation

/// What the submit button reads for one operation, and what it reads while that operation runs.
struct PayInSubmitWording {
    let idle: String
    let busy: String

    init(_ operation: PayabliPayInOperation) {
        switch operation {
        case .capture:
            idle = "Pay"
            busy = "Paying…"
        case .authorize:
            idle = "Authorize"
            busy = "Authorizing…"
        case .storePaymentMethod:
            idle = "Save"
            busy = "Saving…"
        }
    }

    /// The host's wording replaces the idle text only. While a submission runs the button reads the busy text of
    /// the operation being sent, even if the form has since been given another.
    ///
    /// - Parameter operation: the operation the form is set to, whose idle text the button reads at rest.
    /// - Parameter submitting: the operation being sent, whose busy text wins while it runs.
    /// - Parameter hostWording: the host's replacement for the idle text, ignored while a submission runs.
    /// - Returns: the text the button reads.
    static func text(
        showing operation: PayabliPayInOperation,
        submitting: PayabliPayInOperation?,
        hostWording: String?
    ) -> String {
        if let submitting {
            return Self(submitting).busy
        }
        return hostWording ?? Self(operation).idle
    }
}

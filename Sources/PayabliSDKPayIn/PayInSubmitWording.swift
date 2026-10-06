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

    /// The host's wording replaces the idle text only. While a submission runs the button reads the busy text.
    func text(hostWording: String?, isSubmitting: Bool) -> String {
        isSubmitting ? busy : hostWording ?? idle
    }
}

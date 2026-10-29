import Foundation

/// What presenting the terms led to.
///
/// Returning means the request completed, not that a sheet appeared, so a presentation that returned
/// reports what asking afterwards found.
enum TermsPresentation {
    /// Presenting threw.
    case failed(Error)
    /// Presenting returned, and asking whether the merchant accepted answered this.
    case returned(accepted: Result<Bool, Error>)

    /// The line the Tap to Pay tab shows for it.
    var line: String {
        switch self {
        case let .failed(error):
            ActionLine.failed(error)
        case .returned(accepted: .success(true)):
            "returned; now ✓ Accepted"
        case .returned(accepted: .success(false)):
            "returned; still ✗ Not accepted"
        case let .returned(accepted: .failure(error)):
            "returned; could not ask whether accepted: " + error.localizedDescription
        }
    }
}

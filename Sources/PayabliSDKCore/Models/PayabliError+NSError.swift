import Foundation

package extension Error {
    /// The `NSError` an Objective-C caller receives: a `PayabliError` carries its catalog number as the
    /// code and its wire name under `PayabliErrorType`, in `domain`. Anything else bridges as Swift does.
    func payabliNSError(domain: String) -> NSError {
        guard let payabliError = self as? any PayabliError else {
            return self as NSError
        }
        return NSError(
            domain: domain,
            code: payabliError.code,
            userInfo: [
                NSLocalizedDescriptionKey: payabliError.reason,
                "PayabliErrorType": payabliError.type.rawValue
            ]
        )
    }
}

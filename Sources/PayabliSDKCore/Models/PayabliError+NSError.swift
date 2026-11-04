import Foundation

package extension Error {
    /// The `NSError` an Objective-C caller receives: a `PayabliError` carries its catalog number as the
    /// code, its wire name under `PayabliErrorType`, and ``PayabliError/answerUserInfo``, in `domain`. Anything else
    /// bridges as Swift does.
    ///
    /// - Parameter domain: the domain the error is reported in, one of the three an Objective-C host meets.
    /// - Returns: the `NSError` carrying the catalog number as the code; a non-`PayabliError` bridges as Swift does.
    func payabliNSError(domain: String) -> NSError {
        guard let payabliError = self as? any PayabliError else {
            return self as NSError
        }
        var userInfo: [String: Any] = [
            NSLocalizedDescriptionKey: payabliError.errorDescription ?? payabliError.reason,
            "PayabliErrorType": payabliError.type.rawValue
        ]
        userInfo.merge(payabliError.answerUserInfo) { _, answer in answer }
        return NSError(domain: domain, code: payabliError.code, userInfo: userInfo)
    }
}

package extension PayabliError {
    /// The answer's status as an `NSNumber` under `httpStatus` and the service's code as an `NSString` under
    /// `rawCode`, each left out when nil.
    var answerUserInfo: [String: Any] {
        var info: [String: Any] = [:]
        if let httpStatus {
            info["httpStatus"] = NSNumber(value: httpStatus)
        }
        if let rawCode {
            info["rawCode"] = rawCode as NSString
        }
        return info
    }
}

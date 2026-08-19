import Foundation
import PayabliSDKCore

/// What may be said about an error outside the call that raised it: in a log, or
/// in an event payload a host app forwards to its own telemetry.
///
/// A `PayabliError`'s `reason` and `detail` are the service's own words and can
/// quote what was submitted, so they go to the caller and to the screen and stop
/// there. Its `code` says as much as a log needs. `PayabliTTPError` carries text
/// this SDK wrote, which is safe to repeat.
enum ErrorSummary {
    static func of(_ error: Error) -> String {
        switch error {
        case let ttp as PayabliTTPError:
            return String(describing: ttp)
        case let payment as PayabliPaymentError:
            // The umbrella carries the typed error; on its own it bridges to a
            // domain and an ordinal, which is the shape this SDK stopped showing.
            return payment.asPayabliError.code.rawValue
        case let payabli as any PayabliError:
            return payabli.code.rawValue
        default:
            // `NSError` on its own says nothing; the domain and code are what
            // identify a platform failure, and neither is server text.
            let ns = error as NSError
            return "\(ns.domain)(\(ns.code))"
        }
    }
}

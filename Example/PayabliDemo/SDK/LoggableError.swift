import Foundation
import PayabliSDKCore

/// What a log line may say about a failure.
///
/// A `PayabliError`'s description carries the service's own title, detail and per-field
/// messages, which can quote what was submitted, so neither a screen nor the log shows it.
/// The code classifies the failure without repeating anything.
enum LoggableError {
    static func label(for error: Error) -> String {
        if let payabli = error as? any PayabliError {
            return payabli.type.rawValue
        }
        return String(describing: type(of: error))
    }
}

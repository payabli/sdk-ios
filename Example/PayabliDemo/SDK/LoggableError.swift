import Foundation
import PayabliSDKCore

/// What a log line may say about a failure, as opposed to what a screen may show.
///
/// A `PayabliError`'s description now carries the service's own title, detail and
/// per-field messages, which is what makes it worth showing a merchant and what
/// makes it wrong for `os.Logger`: the demo marks its messages `.public`, and a
/// validation message can quote what was submitted. The code classifies the
/// failure without repeating anything.
enum LoggableError {
    static func label(for error: Error) -> String {
        if let payabli = error as? any PayabliError {
            return payabli.code.rawValue
        }
        return String(describing: type(of: error))
    }
}

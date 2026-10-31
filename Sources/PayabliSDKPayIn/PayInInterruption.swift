import Foundation
import PayabliSDKCore

/// How a failure that leaves a submission's outcome open is named.
enum PayInInterruption {
    /// Whether a failure is the caller's cancellation, including the one `URLSession` raises for a cancelled task.
    ///
    /// - Parameter failure: what the send ended in.
    /// - Returns: whether the failure is a cancellation.
    static func isCancellation(_ failure: any Error) -> Bool {
        if failure is CancellationError {
            return true
        }
        return (failure as? URLError)?.code == .cancelled
    }

    /// The type an interrupted submission reports for a failure.
    ///
    /// - Parameter failure: what the send ended in.
    /// - Returns: ``PayabliErrorType/userCancelled`` for a cancellation, the failure's own type for this SDK's
    ///   error, and ``PayabliErrorType/unknown`` for anything else.
    static func type(of failure: any Error) -> PayabliErrorType {
        if isCancellation(failure) {
            return .userCancelled
        }
        return (failure as? any PayabliError)?.type ?? .unknown
    }
}

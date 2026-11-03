import Foundation
import os
import PayabliSDKCore

/// A failure that already carries the message a screen shows.
protocol DisplayedFailure: Error {
    var message: String { get }
}

/// The line a failed action leaves on the Tap to Pay tab.
enum ActionLine {
    /// - Parameter error: what the action threw.
    /// - Returns: "✗ " and the message for the failure's category, with no step name. The error's code goes to
    ///   the log, and its own text to neither.
    static func failed(_ error: Error) -> String {
        if let failure = error as? DisplayedFailure {
            return "✗ \(failure.message)"
        }
        Logger(subsystem: "com.payabli.example.app", category: "TapToPayDiagnostics")
            .error("Action failed: \(LoggableError.label(for: error), privacy: .public)")
        return "✗ \(message(for: error))"
    }

    /// This app's message for a failure's category.
    ///
    /// - Parameter error: what the action threw.
    /// - Returns: the message the failure already carries, or the one for its category, with an error outside the
    ///   catalog read as an unknown outcome, as the SDK reads it.
    static func message(for error: Error) -> String {
        if let failure = error as? DisplayedFailure {
            return failure.message
        }
        return switch (error as? any PayabliError)?.category ?? PayabliErrorType.unknown.category {
        case .declined: "The payment was declined."
        case .retryLater: "That didn't work. Please try again."
        case .outcomeUnknown: "This may have gone through. Check before trying again."
        case .credential: "The terminal couldn't sign in."
        case .configuration: "This terminal isn't set up for that."
        case .invalidRequest: "That request was refused. Check what was entered."
        case .device: "This iPhone can't do that."
        case .internal: "Something went wrong."
        }
    }
}

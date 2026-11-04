import Foundation
import os
import PayabliSDKCore
import PayabliSDKTapToPay

/// A failure that already carries the message a screen shows.
protocol DisplayedFailure: Error {
    var message: String { get }
}

/// A failure already in a screen's words that keeps the code it was raised with.
protocol CodedFailure: Error {
    var eventCode: String { get }
}

/// The line a failed action leaves on the Tap to Pay tab.
enum ActionLine {
    /// The state log's entry for a failed step.
    ///
    /// - Parameters:
    ///   - step: the step that failed, as the log names it.
    ///   - error: what the step threw.
    /// - Returns: the step and the failure's catalog code, or its type for an error the SDK did not raise, never
    ///   its text.
    static func failureEvent(step: String, error: Error) -> String {
        "\(step) failed · code=\(eventCode(for: error))"
    }

    /// The code the state log records for a failure.
    ///
    /// - Parameter error: what an action threw.
    /// - Returns: the catalog code, the code a failure in a screen's words was raised with, or the error's type.
    static func eventCode(for error: Error) -> String {
        if let coded = error as? CodedFailure {
            return coded.eventCode
        }
        if let payabli = error as? any PayabliError {
            return String(payabli.code)
        }
        return String(describing: type(of: error))
    }

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
    /// - Returns: the message the failure already carries, this app's line for a device that cannot run Tap to Pay
    ///   or for a refused activation code, or the one for its category, with an error outside the catalog read as an
    ///   unknown outcome, as the SDK reads it.
    static func message(for error: Error) -> String {
        if let failure = error as? DisplayedFailure {
            return failure.message
        }
        let type = (error as? any PayabliError)?.type
        if let line = ineligibleDeviceLine(type) ?? activationLine(type) {
            return line
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

    /// This app's message for a Tap to Pay failure, which reads whether the card was charged before the category,
    /// since the two can disagree.
    ///
    /// - Parameters:
    ///   - error: what the reader threw.
    ///   - capture: whether the card was charged.
    ///   - paymentTransId: the payment the failure names, if any.
    /// - Returns: a charged or may-have-been-charged line with the payment's ID when it names one, or the category's
    ///   message when the card was not charged.
    static func chargeMessage(for error: Error, capture: PayabliTTPCapture, paymentTransId: String?) -> String {
        let line = switch capture {
        case .charged: "The card was charged. Don't charge it again."
        case .unknown: "This payment may have gone through. Check before charging again."
        case .notCharged: message(for: error)
        }
        guard capture != .notCharged, let paymentTransId else { return line }
        return "\(line) · txn \(paymentTransId)"
    }

    /// This app's line for each failure that means the device cannot run Tap to Pay. The category alone would give all
    /// four one line, and only a refused device has a next step: support, with the device ID.
    ///
    /// - Parameter type: the failure's type, or nil for an error outside the catalog.
    /// - Returns: the line for that type, or nil for any other.
    private static func ineligibleDeviceLine(_ type: PayabliErrorType?) -> String? {
        switch type {
        case .deviceOSUnsupported:
            "This iPhone's iOS version is too old for Tap to Pay. Update iOS and try again."
        case .deviceHardwareUnsupported:
            "This iPhone can't take Tap to Pay payments."
        case .readerDeviceRefused:
            "This iPhone isn't set up for Tap to Pay with this app. Contact Payabli support with the device ID on the Config tab."
        case .deviceIdentityUnavailable:
            "This iPhone can't be identified, so Tap to Pay can't start."
        default:
            nil
        }
    }

    /// This app's line for each refused activation, naming what the operator does next. The category alone would give
    /// six refusals with six different remedies the same two lines.
    ///
    /// - Parameter type: the failure's type, or nil for an error outside the catalog.
    /// - Returns: the line for that type, or nil for any other.
    private static func activationLine(_ type: PayabliErrorType?) -> String? {
        switch type {
        case .activationCodeMalformed:
            "Enter the six-digit activation code."
        case .activationCodeIncorrect:
            "That activation code isn't right. Check it and enter it again."
        case .activationCodeExpired:
            "That activation code has expired. Get a new code and enter it."
        case .activationAttemptsExhausted:
            "Too many wrong codes were entered. Get a new code and enter it."
        case .activationCodeNotIssued:
            "No activation code has been issued for this iPhone. Get a code and enter it."
        case .deviceNotPending:
            "This iPhone isn't waiting for activation. Enable the terminal again."
        default:
            nil
        }
    }
}

import Foundation
import os
import PayabliSDKCore
import PayabliSDKTapToPay

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
    /// - Returns: the message the failure already carries, this app's line for a device that cannot run Tap to Pay,
    ///   or the one for its category, with an error outside the catalog read as an unknown outcome, as the SDK reads it.
    static func message(for error: Error) -> String {
        if let failure = error as? DisplayedFailure {
            return failure.message
        }
        if let line = ineligibleDeviceLine((error as? any PayabliError)?.type) {
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
}

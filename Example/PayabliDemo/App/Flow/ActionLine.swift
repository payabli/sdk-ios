import Foundation

/// The line a failed action leaves on the Tap to Pay tab.
enum ActionLine {
    /// - Parameter error: what the action threw.
    /// - Returns: "✗ " and the error's message, with no step name.
    static func failed(_ error: Error) -> String {
        "✗ \(error.localizedDescription)"
    }
}

import Foundation

/// The line an action leaves beside its step.
enum ActionLine {
    /// - Parameter error: what the action threw.
    /// - Returns: "✗ " and the error's message, with no step name.
    static func failed(_ error: Error) -> String {
        "✗ \(error.localizedDescription)"
    }
}

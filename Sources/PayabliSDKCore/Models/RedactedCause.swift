import Foundation

/// Stands in for a failure whose message cannot be allowed out, keeping only its type name, which carries
/// no subject. A host-thrown error can name the host's endpoint or quote a rejected body, and as `underlying`
/// that text reaches wherever the chain is walked, including a crash reporter the SDK does not scrub.
package struct RedactedCause: Error, CustomStringConvertible, Equatable {
    /// The redacted failure's concrete type, module-qualified.
    package let originalType: String

    package init(_ original: any Error) {
        originalType = String(reflecting: type(of: original))
    }

    package var description: String {
        originalType
    }

    package var localizedDescription: String {
        originalType
    }
}

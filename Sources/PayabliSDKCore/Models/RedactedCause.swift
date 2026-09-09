import Foundation

/// Stands in for a failure whose own message cannot be allowed out, keeping the
/// type name and dropping the text.
///
/// The token provider is host code and can throw anything. `localizedDescription`
/// on a `URLError` names the host's own endpoint, and a decoding failure quotes the
/// body it rejected, so attaching the original as `underlying` puts that text
/// wherever the chain is walked, including a crash reporter the SDK does not scrub.
///
/// A type name carries no subject, which is why it is the part kept. Swift errors
/// carry no capturable stack, so unlike the sibling platform's version this holds
/// the name alone.
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

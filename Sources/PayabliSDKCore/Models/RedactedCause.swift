import Foundation

/// Stands in for a failure whose message cannot be allowed out, keeping only its type name, which carries
/// no subject. A host-thrown error can name the host's endpoint or quote a rejected body, and as `underlying`
/// that text reaches wherever the chain is walked, including a crash reporter the SDK does not scrub.
package struct RedactedCause: Error, CustomStringConvertible, Equatable {
    /// The redacted failure's concrete type, module-qualified.
    package let originalType: String

    package init(_ original: any Error) {
        originalType = Self.typeName(of: original)
    }

    /// The redacted failure's type without its module or enclosing types, as telemetry reports it.
    package var simpleTypeName: String {
        Self.simpleName(originalType)
    }

    /// Drops every module, enclosing-type and local-context qualifier, generic arguments included.
    ///
    /// - Parameter qualified: a type name as `String(reflecting:)` spells it.
    /// - Returns: the type's own name.
    package static func simpleName(_ qualified: String) -> String {
        qualified.replacingOccurrences(
            of: #"(\(unknown context at \$[0-9a-f]+\)|[A-Za-z_][A-Za-z0-9_]*)\."#,
            with: "",
            options: .regularExpression
        )
    }

    /// The type a caller threw. `URLError`, `CocoaError` and `POSIXError` report `NSError` as their dynamic type once
    /// held as an `Error`, so an error in one of their three domains is named by that Swift type, however it was built;
    /// an `NSError` in any other domain stays `NSError`.
    ///
    /// - Parameter original: the failure being redacted.
    /// - Returns: its module-qualified type name.
    private static func typeName(of original: any Error) -> String {
        switch original {
        case is URLError: String(reflecting: URLError.self)
        case is CocoaError: String(reflecting: CocoaError.self)
        case is POSIXError: String(reflecting: POSIXError.self)
        default: String(reflecting: type(of: original))
        }
    }

    package var description: String {
        originalType
    }

    package var localizedDescription: String {
        originalType
    }
}

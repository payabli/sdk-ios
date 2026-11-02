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

    /// The type a caller threw. A Foundation error bridged from `NSError` reports `NSError` as its dynamic type, so
    /// those are named by the Swift type the caller wrote.
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

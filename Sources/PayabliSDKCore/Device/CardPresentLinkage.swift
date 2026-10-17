import Foundation

/// Whether this app linked the card-present product, which is whether it can hold a device record at all.
///
/// A lookup by name, because Core names no capability as a dependency. Every product is a dynamic
/// framework, so the answer is fixed for the process.
package enum CardPresentLinkage {
    /// The Objective-C name of the card-present facade.
    package static let module = "PayabliTTP"

    package static let isLinked: Bool = resolves(module)

    /// Whether a class of this name is loaded in the process.
    ///
    /// - Parameter name: the class's Objective-C runtime name.
    /// - Returns: true when the runtime resolves it.
    package static func resolves(_ name: String) -> Bool {
        NSClassFromString(name) != nil
    }
}

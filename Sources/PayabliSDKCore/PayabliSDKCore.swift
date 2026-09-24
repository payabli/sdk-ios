import Foundation

/// Module-level namespace for `PayabliSDKCore` metadata.
///
/// `PayabliSDKCore` provides the shared infrastructure (authentication,
/// networking, theming, logging, error types) consumed by component
/// modules (`PayabliSDKPayIn`, `PayabliSDKPayout`, etc.). This namespace
/// exposes constants about the module itself.
///
/// > Note: an enum named after its module trips the
/// > `SwiftVerifyEmittedModuleInterface` pass when building with
/// > `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`: the generated
/// > `.swiftinterface` writes fully-qualified type references as
/// > `PayabliSDKCore.PayabliConfig`, which re-parses as "nested type of
/// > the enum" and fails to resolve when library evolution is enabled.
public enum PayabliCore {
    /// The version this source tree releases as. A release tag must equal it, and it moves to the next
    /// version once that release is cut.
    public static var version: String {
        "0.1.0"
    }
}

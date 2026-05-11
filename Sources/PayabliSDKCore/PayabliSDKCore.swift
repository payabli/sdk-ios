import Foundation

/// Module-level namespace for `PayabliSDKCore` metadata.
///
/// `PayabliSDKCore` provides the shared infrastructure (authentication,
/// networking, theming, logging, error types) consumed by component
/// modules (`PayabliSDKPayIn`, `PayabliSDKPayout`, etc.). This namespace
/// exposes constants about the module itself.
///
/// > Note: the enum is named `PayabliCore` rather than `PayabliSDKCore`
/// > on purpose. Naming the namespace the same as the module trips the
/// > `SwiftVerifyEmittedModuleInterface` pass when building with
/// > `BUILD_LIBRARY_FOR_DISTRIBUTION=YES`: the generated
/// > `.swiftinterface` writes fully-qualified type references as
/// > `PayabliSDKCore.PayabliConfig`, which re-parses as "nested type of
/// > the enum" and fails to resolve when library evolution is enabled.
public enum PayabliCore {
    public static var version: String {
        Bundle(for: VersionMarker.self)
            .infoDictionary?["CFBundleShortVersionString"] as? String
            ?? "0.0.0"
    }

    private final class VersionMarker {}
}

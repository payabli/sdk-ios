import Foundation

/// Protocol every PayabliSDK component (PayIn, Payout, Reporting, Onboarding) conforms to.
/// Configuration methods are `@MainActor` because components own SwiftUI / `ObservableObject` state;
/// the static requirements are `nonisolated` because they are compile-time constants.
@MainActor
package protocol PayabliComponent: AnyObject {
    /// Unique identifier for this component (e.g. `"payin"`, `"payout"`).
    nonisolated static var componentId: String { get }

    /// Required session tier for this component's operations.
    nonisolated static var sessionTier: PayabliSessionTier { get }

    /// Required permissions this component needs from the session.
    nonisolated static var requiredPermissions: [String] { get }

    /// Initialize the component with shared configuration.
    func configure(config: PayabliConfig)

    /// Legacy compatibility entry point for integrations compiled against the
    /// original component protocol. New component-specific style APIs replace
    /// the shared theme object.
    func configure(config: PayabliConfig, theme: PayabliTheme)
}

package extension PayabliComponent {
    func configure(config: PayabliConfig) {
        configure(config: config, theme: .default)
    }

    func configure(config: PayabliConfig, theme: PayabliTheme) {
        fatalError("PayabliComponent conformers must implement configure(config:) or configure(config:theme:).")
    }
}

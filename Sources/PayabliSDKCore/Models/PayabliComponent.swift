import Foundation

/// Protocol all PayabliSDK components must conform to.
///
/// Enables uniform lifecycle management across PayIn, Payout, Reporting, and
/// Onboarding components. See PRD §28.3.
///
/// `configure(config:theme:)` is `@MainActor` because components own SwiftUI /
/// `ObservableObject` state. The static requirements are `nonisolated` since
/// they are compile-time constants.
@MainActor
public protocol PayabliComponent: AnyObject {
    /// Unique identifier for this component (e.g. `"payin"`, `"payout"`).
    nonisolated static var componentId: String { get }

    /// Required session tier for this component's operations.
    nonisolated static var sessionTier: PayabliSessionTier { get }

    /// Required permissions this component needs from the session.
    nonisolated static var requiredPermissions: [String] { get }

    /// Initialize the component with shared configuration.
    func configure(config: PayabliConfig, theme: PayabliTheme)
}

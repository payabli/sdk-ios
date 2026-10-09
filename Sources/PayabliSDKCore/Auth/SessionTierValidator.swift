import Foundation

/// Checks the session's tier against a component's static requirement, throwing
/// `PayabliGenericError(.permissionDenied)` on a mismatch. Every session is detected as Tier 1.
enum SessionTierValidator {
    static func validate(
        component: any PayabliComponent.Type,
        against config: PayabliConfig
    ) throws {
        let required = component.sessionTier
        let actual = detectedTier(from: config)
        guard actual.rawValue >= required.rawValue else {
            throw PayabliGenericError(
                type: .permissionDenied,
                reason: "Session tier mismatch",
                detail: "\(component.componentId) requires tier \(required.rawValue); session is tier \(actual.rawValue)."
            )
        }
    }

    /// Always Tier 1: nothing in the configuration carries a tier.
    static func detectedTier(from config: PayabliConfig) -> PayabliSessionTier {
        .tier1Transactional
    }
}

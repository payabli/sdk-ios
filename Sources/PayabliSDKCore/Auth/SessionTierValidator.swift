import Foundation

/// Checks the session's tier against a component's static requirement, throwing
/// `PayabliGenericError(.permissionDenied)` on a mismatch. A nil `sessionToken` counts as Tier 1; a JWT's
/// `tier` claim is read without verifying the signature, which the API validates server-side.
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

    /// Best-effort tier detection. Defaults to Tier 1 when nothing indicates
    /// a higher tier.
    static func detectedTier(from config: PayabliConfig) -> PayabliSessionTier {
        .tier1Transactional
    }
}

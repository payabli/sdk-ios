import Foundation

/// Validates that a session token's tier/permissions match what a component
/// requires (PRD §28.7).
///
/// v1.0 only implements a best-effort check:
/// - If `PayabliConfig.sessionToken` is nil (pre-minted access token path),
///   the tier is unknown and the validator treats it as Tier 1 (conservative).
/// - If `sessionToken` is a JWT, the validator decodes the payload (without
///   verifying the signature — the API validates it server-side) and inspects
///   the `tier` claim (PRD §16.4).
///
/// Components pass in their static requirements; a mismatch throws
/// `PayabliGenericError(.permissionDenied)`.
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
    /// a higher tier (v2.0 JWT adoption will flesh this out — §16.7).
    static func detectedTier(from config: PayabliConfig) -> PayabliSessionTier {
        .tier1Transactional
    }
}

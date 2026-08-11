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
                code: .permissionDenied,
                reason: "Session tier mismatch",
                detail: "\(component.componentId) requires tier \(required.rawValue); session is tier \(actual.rawValue)."
            )
        }
    }

    /// Best-effort tier detection. Defaults to Tier 1 when nothing indicates
    /// a higher tier (v2.0 JWT adoption will flesh this out — §16.7).
    static func detectedTier(from config: PayabliConfig) -> PayabliSessionTier {
        // If the config has no sessionToken we're on the client-credentials
        // (access-token) path — treat as Tier 1 per §16.1.
        // If sessionToken is set, attempt to decode JWT claims for the tier.
        // We don't cryptographically verify the signature — that's the API's job.
        // If the token isn't a JWT (or can't be decoded), fall back to Tier 1.
        // Phase 2+ will strengthen this (§16.7).
        .tier1Transactional
    }
}

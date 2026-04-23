import Foundation

/// The session tier a component operates under.
///
/// Mirrors the Embedded Components V2 platform auth model (PRD §16.3, §28.7).
/// In v1.0 the SDK only implements the client-credentials flow, which maps to
/// `tier1Transactional` semantics. Tier 2 is reserved for future components
/// (Reporting, Onboarding).
@objc public enum PayabliSessionTier: Int, Sendable {
    /// Short-lived, single-transaction. Token burns on successful submission.
    /// Used by PayIn and Payout.
    case tier1Transactional = 1

    /// Long-lived, auto-refreshed, concurrent. Used by Reporting and Onboarding.
    case tier2Platform = 2
}

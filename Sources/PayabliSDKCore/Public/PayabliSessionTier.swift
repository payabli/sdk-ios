import Foundation

/// The session tier a component operates under. The SDK implements only the client-credentials flow,
/// which maps to `tier1Transactional`; Tier 2 is reserved for Reporting and Onboarding.
@objc package enum PayabliSessionTier: Int, Sendable {
    /// Short-lived, single-transaction. Token burns on successful submission.
    /// Used by PayIn and Payout.
    case tier1Transactional = 1

    /// Long-lived, auto-refreshed, concurrent. Used by Reporting and Onboarding.
    case tier2Platform = 2
}

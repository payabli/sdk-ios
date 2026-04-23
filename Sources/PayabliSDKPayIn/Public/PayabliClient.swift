import Foundation

/// Backwards-compatible alias for `PayabliPayIn` (PRD §5.3 FR-6.1 names the
/// singleton `PayabliClient.shared`).
///
/// The rest of the SDK uses `PayabliPayIn` because it makes the component
/// suite architecture (§28) explicit. Both names resolve to the same type.
public typealias PayabliClient = PayabliPayIn

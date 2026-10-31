import Foundation

/// A refusal of the charge itself.
///
/// ``TapToPayError/refusal`` carries one when the failure refused the charge, and is nil for every other
/// failure. Which case is present is what a host branches on: it names what this refusal asks them to do,
/// and ``TapToPayError/type`` is read exactly as for every other failure.
public enum TapToPayChargeRefusal: Sendable, Equatable {
    /// The paypoint requires customer fields the charge did not carry.
    ///
    /// - Parameter requiredFields: Every identifier the paypoint requires, all of which must be set, named by
    ///   its ``PayabliTTPCustomerData`` property, or as the paypoint names it when it has none. Empty when the
    ///   refusal named none.
    case customerDataRefused(requiredFields: [String])
}

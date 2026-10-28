import Foundation

/// A refusal of the charge itself.
///
/// ``TapToPayError/refusal`` carries one when the failure refused the charge, and is nil for every other
/// failure. Which case is present is what a host branches on: it names what this refusal asks them to do,
/// and ``TapToPayError/type`` is read exactly as for every other failure.
public enum TapToPayChargeRefusal: Sendable, Equatable {
    /// The paypoint requires customer fields the charge did not carry.
    ///
    /// - Parameter requiredFields: The customer fields to collect before charging again, empty when the
    ///   refusal named none.
    case customerDataRefused(requiredFields: [String])
}

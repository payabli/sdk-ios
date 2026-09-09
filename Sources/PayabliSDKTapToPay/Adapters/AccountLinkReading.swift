import Foundation
#if canImport(PayabliCardReaderCore)
    import PayabliCardReaderCore
#endif

/// The one question `areTermsAccepted()` asks of a card reader.
///
/// A reader cannot be built without hardware, so this is what a test answers in
/// its place. Everything else the adapter does still needs a real reader.
/// `TapToPayProvider` is the provider abstraction; this is not a second one.
protocol AccountLinkReading: AnyObject {
    /// Whether the merchant has accepted the terms the platform requires.
    func isAccountLinked() async throws -> Bool
}

#if canImport(PayabliCardReaderCore)
    /// The vendored reader already answers this, so the conformance is empty.
    extension FiservTTPCardReader: AccountLinkReading {}
#endif

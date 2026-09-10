import Foundation
#if canImport(PayabliCardReaderCore)
    import PayabliCardReaderCore
#endif

/// What the terms surface asks of a card reader: whether the merchant has accepted, and the request to
/// present the platform's sheet so they can.
///
/// A reader cannot be built without hardware, so this is what a test answers in
/// its place. Everything else the adapter does still needs a real reader.
/// `TapToPayProvider` is the provider abstraction; this is not a second one.
///
/// Both members belong to one reader instance rather than to two seams: presenting the sheet needs the
/// session token that reader obtained, and asking again afterwards is how the answer changes.
protocol AccountLinking: AnyObject {
    /// Whether the merchant has accepted the terms the platform requires.
    func isAccountLinked() async throws -> Bool

    /// Presents the platform's own terms sheet. Returns once the merchant has finished with it.
    ///
    /// The reader holds the session token this needs, which is why it is asked of the reader rather
    /// than performed anywhere above it. Nothing here accepts on the merchant's behalf: the sheet is
    /// the platform's and the merchant taps it.
    func linkAccount() async throws
}

#if canImport(PayabliCardReaderCore)
    /// The vendored reader already answers both, so the conformance is empty.
    extension FiservTTPCardReader: AccountLinking {}
#endif

import Foundation
#if canImport(PayabliCardReaderCore)
    internal import PayabliCardReaderCore
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

    /// Asks the platform to present its own terms. Returns once the request is done, which is not
    /// the same as a sheet having been shown: a merchant who has already accepted needs none, and
    /// the request then completes without presenting anything.
    ///
    /// The reader holds the session token this needs, which is why it is asked of the reader rather
    /// than performed anywhere above it. Nothing here accepts on the merchant's behalf: the sheet is
    /// the platform's and the merchant taps it.
    func linkAccount() async throws
}

/// The rest of what `prepareReader()` drives, on the same reader instance.
///
/// Separate from `AccountLinking` because the terms surface asks only the two questions above,
/// and widening that seam would make every terms test answer setup calls it never makes.
///
/// A test supplies its own, because `isAccountLinked()` reaches `PaymentCardReader` and a
/// simulator has none. The session token is not the wall: `requestSessionToken()` is an ordinary
/// `URLSession` call and answers a stub.
protocol ReaderSetup: AccountLinking {
    func requestSessionToken() async throws

    /// Opens the reader session, reporting what the reader does while it runs.
    ///
    /// - Parameter onReaderEvent: Called for each event until the session ends.
    ///   Configuration progress is raised during this call, so the handler
    ///   arrives with it rather than being set afterwards.
    func initializeSession(onReaderEvent: @escaping @MainActor (TapToPayReaderEvent) -> Void) async throws
}

#if canImport(PayabliCardReaderCore)
    /// The vendored reader answers three of the four as they stand.
    extension FiservTTPCardReader: AccountLinking {}

    extension FiservTTPCardReader: ReaderSetup {
        /// The fourth speaks the platform's event vocabulary, so it is converted
        /// here. This is the boundary the rest of the SDK is kept behind.
        func initializeSession(onReaderEvent: @escaping @MainActor (TapToPayReaderEvent) -> Void) async throws {
            try await initializeSession(eventHandler: { event in
                guard let mapped = FiservCardReader.mapReaderEvent(event) else { return }
                onReaderEvent(mapped)
            })
        }
    }
#endif

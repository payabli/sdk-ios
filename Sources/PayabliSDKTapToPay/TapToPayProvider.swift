import Foundation

/// Provider-agnostic abstraction over the contactless NFC reader; the facade depends only on this. An atomic
/// provider (`PayabliCardReaderCore`, read and charge in one call) returns the processor response in
/// `providerResponseJSON`; a collect-then-charge provider ignores the merchant IDs and fills `encryptedPayload`.
package protocol TapToPayProvider: AnyObject, Sendable {
    /// Identifier sent in the API payload `provider` field so the backend
    /// routes decryption correctly.
    static var providerId: String { get }

    /// Validates that the device + OS + entitlements are acceptable, before any UI is presented. Runs before
    /// `/config` returns credentials, so implementations must NOT require them: validate only platform,
    /// hardware and entitlements.
    func checkEligibility() async -> Result<Void, PayabliTTPError>

    /// Applies the raw credentials block from `/api/v2/device/taptopay/config/{entry}`, validating its keys and
    /// throwing a `PayabliTTPError` such as `.readerSetupFailed(reason:)` before `prepareReader()` when one is
    /// missing or malformed. Credentials live only in RAM and must be cleared in `cleanUp()`.
    func configure(credentials: [String: String]) throws

    /// Prepares the reader: connect, request a session token, open the session.
    /// Presenting the platform's terms is `presentTerms()`, never this.
    /// `configure(credentials:)` must have succeeded before this call.
    ///
    /// - Parameter onReaderEvent: Called for each `TapToPayReaderEvent` the
    ///   reader raises, until `cleanUp()`. It is a parameter here rather than a
    ///   property set separately because configuration progress arrives during
    ///   this call: a handler installed afterwards would miss the one thing it
    ///   exists to report.
    func prepareReader(onReaderEvent: @escaping @MainActor @Sendable (TapToPayReaderEvent) -> Void) async throws

    /// Whether the merchant has accepted the terms their platform requires
    /// before it will take a contactless payment.
    ///
    /// Called by the facade on demand rather than during a phase, so it may
    /// arrive at any point. Implementations answer from the platform each time
    /// instead of caching, since acceptance can be granted or withdrawn outside
    /// this process.
    ///
    /// A platform that requires no acceptance returns `true`.
    ///
    /// Must throw `PayabliTTPError.readerSetupFailed(reason:)` when there is no
    /// reader to ask, so a caller can tell "not accepted" from "cannot answer".
    func areTermsAccepted() async throws -> Bool

    /// Asks the platform to present its own terms so the merchant can accept, and
    /// returns once the request is done.
    ///
    /// Nothing here accepts on the merchant's behalf. The sheet belongs to the
    /// platform and the merchant taps it, so returning without error means the
    /// request completed, not that a sheet was shown: a platform that requires no
    /// acceptance returns without presenting anything. `areTermsAccepted()` is what
    /// answers where the merchant stands afterwards.
    ///
    /// Called by the facade on demand, from a screen the host chose. A platform
    /// that requires no acceptance returns without doing anything.
    ///
    /// Must throw `PayabliTTPError.readerSetupFailed(reason:)` when there is no
    /// reader to present from, for the same reason `areTermsAccepted()` does.
    func presentTerms() async throws

    /// Runs the NFC interaction and (for atomic providers like Fiserv) the
    /// actual charge. Providers that only collect card data should ignore the
    /// merchant correlation IDs and populate `encryptedPayload` in the result.
    func startReading(_ request: CardReadRequest) async throws -> CardReadResult

    /// Cancels an active reader session.
    func cancelReading() async

    /// Cleans up reader resources.
    func cleanUp() async
}

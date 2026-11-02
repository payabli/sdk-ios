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
    ///
    /// - Returns: whether this device is eligible to read cards, as success or the refusal naming why it is not.
    func checkEligibility() async -> Result<Void, PayabliTTPError>

    /// Applies the raw credentials block from `/api/v2/device/taptopay/config/{entry}`, validating its keys and
    /// throwing a `PayabliTTPError` such as `.readerCredentialsUnusable` before `prepareReader()` when one is
    /// missing or malformed. Credentials live only in RAM and must be cleared in `cleanUp()`.
    ///
    /// - Parameter credentials: the raw `providerCredentials` block, keyed as the configuration route sent it.
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

    /// Whether the merchant has accepted the terms the platform requires before it takes a contactless payment.
    ///
    /// Implementations answer from the platform each time, since acceptance can be granted or withdrawn
    /// outside this process.
    ///
    /// - Returns: whether the merchant has accepted; a platform that requires no acceptance answers `true`.
    /// - Throws: `.guardFailed` when there is no reader to ask, so a caller can tell "not accepted" from "cannot answer".
    func areTermsAccepted() async throws -> Bool

    /// Presents the platform's own terms and returns once the request is done. Returning without error says the
    /// request completed, not that a sheet was shown, so `areTermsAccepted()` answers where the merchant stands.
    /// Nothing here accepts on the merchant's behalf.
    ///
    /// - Throws: `PayabliTTPError.guardFailed(reason:)` when there is no reader to present from.
    func presentTerms() async throws

    /// Runs the NFC interaction and (for atomic providers like Fiserv) the
    /// actual charge. Providers that only collect card data should ignore the
    /// merchant correlation IDs and populate `encryptedPayload` in the result.
    ///
    /// - Parameter request: the charge to read a card for, with the amount and the merchant correlation IDs.
    /// - Returns: the result of the read, carrying the processor response or the collected card data.
    func startReading(_ request: CardReadRequest) async throws -> CardReadResult

    /// Cancels an active reader session.
    func cancelReading() async

    /// Cleans up reader resources.
    func cleanUp() async
}

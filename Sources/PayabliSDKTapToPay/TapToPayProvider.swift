import Foundation

/// Provider-agnostic abstraction over the contactless NFC card reader.
///
/// Implementations (the vendored `PayabliCardReaderCore` adapter, future
/// Apple ProximityReader direct, etc.) are registered with
/// `TapToPayProviderFactory`. The TTP facade depends only on this protocol
/// (PRD FR-11A.1..7).
///
/// v1.0 only ships the `PayabliCardReaderCore` adapter. Because that
/// adapter's `charges(amount:)` is atomic (NFC read + charge in a single SDK
/// call), `startReading` receives a `CardReadRequest` (amount + merchant
/// correlation IDs) and returns a `CardReadResult` that carries the full
/// processor response JSON under `providerResponseJSON`. Future providers
/// that follow a "collect encrypted payload, charge server-side" flow can
/// ignore the merchant IDs and populate `encryptedPayload` instead.
///
/// `CardReadRequest` and `CardReadResult` are defined in
/// `Models/TapToPayCardRead.swift` (PRD §7.2).
package protocol TapToPayProvider: AnyObject, Sendable {
    /// Identifier sent in the API payload `provider` field so the backend
    /// routes decryption correctly (PRD FR-11J.3).
    static var providerId: String { get }

    /// Validates that the device + OS + entitlements are acceptable.
    /// Called before any UI is presented (PRD FR-11J.2).
    ///
    /// Implementations must NOT require runtime credentials to be injected
    /// yet: eligibility runs before `/config` returns them. Only validate
    /// platform / hardware / entitlements here.
    func checkEligibility() async -> Result<Void, PayabliTTPError>

    /// Applies the provider-specific credentials block returned by
    /// `/api/v2/device/taptopay/config/{entry}` (PRD FR-11B.3). The facade is
    /// provider-agnostic — it forwards the raw dictionary as received from the
    /// backend and the adapter is responsible for validating and converting
    /// the keys it cares about.
    ///
    /// Must throw `PayabliTTPError.readerSetupFailed(reason:)` (or any other
    /// `PayabliTTPError`) when required keys are missing or malformed so the
    /// initialization fails loudly before `prepareReader()` is attempted.
    ///
    /// Credentials must live only in RAM (NFR-5D); implementations must clear
    /// them in `cleanUp()`.
    func configure(credentials: [String: String]) throws

    /// Prepares the reader (connect, link account, open session).
    /// `configure(credentials:)` must have succeeded before this call.
    func prepareReader() async throws

    /// Runs the NFC interaction and (for atomic providers like Fiserv) the
    /// actual charge. Providers that only collect card data should ignore the
    /// merchant correlation IDs and populate `encryptedPayload` in the result.
    func startReading(_ request: CardReadRequest) async throws -> CardReadResult

    /// Cancels an active reader session.
    func cancelReading() async

    /// Cleans up reader resources.
    func cleanUp() async
}

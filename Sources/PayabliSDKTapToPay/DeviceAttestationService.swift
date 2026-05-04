import Foundation

/// The result of a device attestation flow.
public struct AttestationResult: Sendable {
    public let keyId: String
    public let deviceId: String

    public init(keyId: String, deviceId: String) {
        self.keyId = keyId
        self.deviceId = deviceId
    }
}

/// A per-request integrity assertion (PRD §18.2).
public struct AssertionHeaders: Sendable {
    public let assertion: String
    public let keyId: String
    public let deviceId: String
    public let timestamp: String

    public var asDictionary: [String: String] {
        [
            "X-App-Assertion": assertion,
            "X-App-KeyId": keyId,
            "X-Device-Id": deviceId,
            "X-Assertion-Timestamp": timestamp
        ]
    }
}

/// Device attestation abstraction (PRD §18).
///
/// Real-world implementations wrap `DCAppAttestService` (iOS 14+) plus the
/// Payabli backend attestation endpoints. Tests use a mock that short-circuits
/// to deterministic IDs.
///
/// The real `DCAppAttestService` integration lives in Phase 6 / production —
/// this protocol isolates it so the rest of the TTP flow is unit-testable
/// without iOS entitlements or network access.
public protocol DeviceAttestationService: AnyObject, Sendable {
    /// Whether attestation has already been performed on this device (i.e.
    /// `keyId` + `deviceId` are cached). Used to pick warm vs cold path
    /// during `initialize()` (PRD §18.3).
    var isAlreadyAttested: Bool { get }

    /// The backend-assigned `deviceId` persisted from a prior successful
    /// attestation, or `nil` if the device has not been attested yet. The
    /// facade uses this on the warm path where `attest()` is skipped.
    var cachedDeviceId: String? { get }

    /// Runs the first-run attestation flow: challenge → register → attest.
    /// Throws `PayabliTTPError.devicePendingActivation` if the backend returns
    /// `status == "pending"` (PRD FR-11F.1).
    func attest(entry: String, appId: String) async throws -> AttestationResult

    /// Produces fresh `AssertionHeaders` (signed over a current timestamp) for
    /// the next protected request. PRD §18.2.
    func generateAssertion() async throws -> AssertionHeaders

    /// Activates a pending device with an activation code issued out-of-band
    /// by the partner (e.g. from their admin dashboard). The SDK does not
    /// request the code itself — the partner is responsible for delivering it
    /// to the device user. PRD §9.7.
    func activateDevice(activationCode: String, entry: String) async throws

    /// Clears cached attestation state (triggers a full re-attestation on next
    /// `initialize()`). Called on 401 from the config endpoint (PRD §18.4).
    func clearCache()
}

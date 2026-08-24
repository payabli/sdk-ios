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

    public init(assertion: String, keyId: String, deviceId: String, timestamp: String) {
        self.assertion = assertion
        self.keyId = keyId
        self.deviceId = deviceId
        self.timestamp = timestamp
    }

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
    /// Whether this device holds a binding **for this entry point**. Used to pick
    /// warm versus cold path during `initialize()` (PRD §18.3).
    ///
    /// Scoped to the entry point: a handle issued under another one is not this
    /// device's enrolment here, and presenting it is refused. The sibling SDK
    /// scopes the same question the same way.
    ///
    /// Asynchronous because answering it means asking the platform whether the
    /// key the binding names is still held, which is the same check the sibling
    /// SDK makes by comparing thumbprints.
    ///
    /// Raises when the store could not be read. That is a third answer and not a
    /// `false`: `false` runs the cold sequence, and running it against a paypoint
    /// that is already enrolled registers a second device for it.
    func isAttested(for entry: String) async throws -> Bool

    /// The backend-assigned `deviceId` this entry point was registered under, or
    /// `nil` when it holds no binding. The facade uses this on the warm path
    /// where `attest()` is skipped.
    func cachedDeviceId(for entry: String) throws -> String?

    /// Runs the first-run attestation flow: challenge → register → attest.
    /// Throws `PayabliTTPError.devicePendingActivation` if the backend returns
    /// `status == "pending"` (PRD FR-11F.1).
    func attest(entry: String, appId: String) async throws -> AttestationResult

    /// Produces fresh `AssertionHeaders` (signed over a current timestamp) for
    /// the next protected request. PRD §18.2.
    ///
    /// Takes the entry point because the headers name the handle this device
    /// holds for it, and a handle from another paypoint is refused.
    func generateAssertion(for entry: String) async throws -> AssertionHeaders

    /// Activates a pending device with an activation code issued out-of-band
    /// by the partner (e.g. from their admin dashboard). The SDK does not
    /// request the code itself — the partner is responsible for delivering it
    /// to the device user. PRD §9.7.
    func activateDevice(activationCode: String, entry: String) async throws

    /// Drops this entry point's binding, so the next `initialize()` for it runs
    /// the cold sequence. Called on 401 from the config endpoint (PRD §18.4).
    /// Every other entry point's binding is left alone.
    func clearCache(for entry: String)
}

import Foundation

/// The result of a device attestation flow.
package struct AttestationResult: Sendable {
    package let keyId: String
    package let deviceId: String

    package init(keyId: String, deviceId: String) {
        self.keyId = keyId
        self.deviceId = deviceId
    }
}

/// A per-request integrity assertion (PRD §18.2).
package struct AssertionHeaders: Sendable {
    package let assertion: String
    package let keyId: String
    package let deviceId: String
    package let timestamp: String

    package init(assertion: String, keyId: String, deviceId: String, timestamp: String) {
        self.assertion = assertion
        self.keyId = keyId
        self.deviceId = deviceId
        self.timestamp = timestamp
    }

    package var asDictionary: [String: String] {
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
package protocol DeviceAttestationService: AnyObject, Sendable {
    /// Whether this device holds a binding for this entry point, which picks the
    /// warm or cold path during `initialize()` (PRD §18.3). A handle issued under
    /// another entry point is not this device's enrolment here.
    ///
    /// Asynchronous because answering it means asking the platform whether the key
    /// the binding names is still held.
    ///
    /// Raises when the store could not be read, which is a third answer: `false`
    /// runs the cold sequence and registers a second device for a paypoint that is
    /// already enrolled.
    func isAttested(for entry: String) async throws -> Bool

    /// The backend-assigned `deviceId` this entry point was registered under, or
    /// `nil` when it holds no binding.
    func cachedDeviceId(for entry: String) throws -> String?

    /// Runs the first-run attestation flow: challenge → register → attest.
    /// Throws `PayabliTTPError.devicePendingActivation` if the backend returns
    /// `status == "pending"` (PRD FR-11F.1).
    func attest(entry: String, appId: String) async throws -> AttestationResult

    /// Produces fresh `AssertionHeaders` (signed over a current timestamp) for the
    /// next protected request, naming the handle this device holds for `entry`.
    /// PRD §18.2.
    func generateAssertion(for entry: String) async throws -> AssertionHeaders

    /// Activates a pending device with an activation code issued out-of-band
    /// by the partner (e.g. from their admin dashboard). The SDK does not
    /// request the code itself — the partner is responsible for delivering it
    /// to the device user. PRD §9.7.
    func activateDevice(activationCode: String, entry: String) async throws

    /// Drops this entry point's binding unconditionally, so the next `initialize()`
    /// for it runs the cold sequence. Every other entry point's binding is left
    /// alone.
    ///
    /// A reset for a host that wants this device enrolled again. Nothing in the SDK
    /// calls it: a refusal is a statement about the binding that was presented, and
    /// dropping by entry point alone takes a binding attested since. Refusals use
    /// `forgetRefusedBinding(entry:deviceId:keyId:)`, and a conformer that puts its
    /// cleanup here will not see one.
    ///
    /// Raises when the store refuses the drop. A binding left behind names a key the
    /// platform signs with, so it reads as sound on the next warm check and is sent
    /// again.
    func clearCache(for entry: String) throws

    /// Drops the binding a refusal was about, while it is still the one held.
    ///
    /// For a caller that presented a handle, went away, and came back with a
    /// refusal: the entry point may hold a binding attested in that window, and
    /// dropping by entry point takes that one for an answer about a different
    /// device. The comparison and the removal happen under one lock.
    ///
    /// Answers whether it dropped anything, and raises when the store refuses.
    @discardableResult
    func forgetRefusedBinding(entry: String, deviceId: String, keyId: String) throws -> Bool
}

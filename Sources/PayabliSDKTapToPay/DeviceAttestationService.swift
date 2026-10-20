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

/// A per-request integrity assertion.
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

/// Device attestation abstraction. Production wraps `DCAppAttestService` (iOS 14+) and the backend
/// attestation endpoints; tests substitute a mock returning deterministic IDs, so the TTP flow is
/// unit-testable without iOS entitlements or network access.
package protocol DeviceAttestationService: AnyObject, Sendable {
    /// Whether this device holds a binding for `entry` whose key the platform still holds, picking the warm or
    /// cold path in `initialize()`. Raises, keeping the binding, when the store or the key check cannot answer:
    /// `false` there registers a second device for an enrolled paypoint.
    ///
    /// - Parameter entry: the entry point whose held binding is asked about.
    /// - Returns: whether the entry point is enrolled, false with no binding held or one naming an unheld key.
    func isAttested(for entry: String) async throws -> Bool

    /// The backend-assigned `deviceId` this entry point was registered under, or
    /// `nil` when it holds no binding.
    ///
    /// - Parameter entry: the entry point whose registration is asked about.
    /// - Returns: the entry point's `deviceId`, or `nil` while it holds no binding.
    func cachedDeviceId(for entry: String) throws -> String?

    /// Runs the first-run attestation flow: challenge → register → attest.
    /// Throws `PayabliTTPError.devicePendingActivation` if the backend returns
    /// `status == "pending"`.
    ///
    /// - Parameter entry: the entry point the device is enrolling against.
    /// - Returns: the key and device ids the entry point's binding names.
    func attest(entry: String) async throws -> AttestationResult

    /// Produces fresh `AssertionHeaders` (signed over a current timestamp) for the
    /// next protected request, naming the handle this device holds for `entry`.
    ///
    /// - Parameter entry: the entry point whose stored binding signs.
    /// - Returns: the headers to send with the next protected request.
    func generateAssertion(for entry: String) async throws -> AssertionHeaders

    /// Activates a pending device with an activation code issued out-of-band by the partner (e.g. from
    /// their admin dashboard), who delivers it to the device user. The SDK does not request the code itself.
    ///
    /// - Parameter activationCode: the code the partner issued out of band and delivered to the device user.
    /// - Parameter entry: the entry point whose pending device is activated.
    /// - Parameter activationId: the device handle the activation is for, matched against the binding held.
    func activateDevice(activationCode: String, entry: String, activationId: String) async throws

    /// Drops this entry point's binding unconditionally, so its next `initialize()` runs the cold sequence.
    ///
    /// A host's reset; nothing in the SDK calls it, and a refusal is not one: `forgetRefusedBinding` drops
    /// the binding it named, because dropping by entry point alone takes a binding attested since.
    ///
    /// - Parameter entry: the entry point whose binding is dropped; every other entry point's binding stays.
    /// - Throws: when the store refuses the drop.
    func clearCache(for entry: String) throws

    /// Drops the binding a refusal was about, while it is still the one held.
    ///
    /// The entry point may hold a binding attested while the caller was away, so dropping by entry point
    /// alone takes that one for an answer about a different device.
    ///
    /// - Parameter entry: the entry point the refused binding names.
    /// - Parameter deviceId: the device handle the refusal was about, matched against the one held.
    /// - Parameter keyId: the key the refused binding names.
    /// - Returns: whether the binding was still the one held and was dropped.
    /// - Throws: when the store refuses the drop.
    @discardableResult
    func forgetRefusedBinding(entry: String, deviceId: String, keyId: String) throws -> Bool
}

package struct ActivationRegistrationChanged: Error {
    package init() {}
}

/// The assertion that signs `/activate` could not be produced, so `/activate` was not sent. It lands by
/// `hostError`'s code, because no activation code repairs a device that cannot sign.
package struct ActivationSigningFailed: Error {
    package let hostError: TapToPayError

    package init(hostError: TapToPayError) {
        self.hostError = hostError
    }
}

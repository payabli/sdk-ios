import CryptoKit
import Foundation
import PayabliSDKCore

// MARK: - AppAttestService

/// Production `DeviceAttestationService` (PRD §18).
///
/// Bridges Apple's `DCAppAttestService` with the Payabli backend so a TTP
/// session can prove it runs on a genuine, unmodified iOS app:
///
/// - First-run flow (`attest`): challenge → register → generate key →
///   attest key → post attestation. Records the paypoint's binding in the
///   Keychain (PRD §22.1).
/// - Warm path: when this paypoint holds a binding whose key the platform will
///   still sign with, `attest` is skipped and per-request assertions are
///   produced by `generateAssertion()` (PRD §18.2).
/// - Activation (`activateDevice`) consumes an out-of-band code supplied by
///   the partner to drive the pending-device → active-device transition
///   (PRD §9.7). The SDK does not request the code itself.
///
/// `entry` and `appId` are supplied per call by the facade (`PayabliTTP`)
/// to match the `DeviceAttestationService` protocol — they are never
/// cached on this service.
///
/// Companion files (same folder, PRD §7.2):
///   - `AppAttestService+Attest.swift`     — attestation + assertions
///   - `AppAttestService+Activation.swift` — `/activate` endpoint
///   - `AppAttestService+Requests.swift`   — shared envelope plumbing
///   - `AppAttestService+Defaults.swift`   — hardware-identifier providers
///   - `AppAttestWireFormat.swift`         — request/response DTOs
public final class AppAttestService: DeviceAttestationService, @unchecked Sendable {
    let transport: any PayabliTransport
    let attestor: AppAttestor
    let storage: SecureStorage
    let bindingStore: AttestedDeviceStore
    let logger = PayabliLogger(category: .taptopay)

    // Injected so tests on macOS can substitute deterministic values.
    //
    // The hardware identifier reads and may write the store, so it raises. The
    // others read the platform and cannot fail.
    let hardwareIdProvider: @Sendable () throws -> String
    let modelProvider: @Sendable () -> String
    let osVersionProvider: @Sendable () -> String

    public convenience init(
        transport: any PayabliTransport,
        attestor: AppAttestor,
        storage: SecureStorage
    ) {
        self.init(
            transport: transport,
            attestor: attestor,
            storage: storage,
            hardwareIdProvider: { try InstallIdentifier.hardwareId(storage: storage) },
            modelProvider: AppAttestService.defaultModel,
            osVersionProvider: AppAttestService.defaultOSVersion
        )
    }

    init(
        transport: any PayabliTransport,
        attestor: AppAttestor,
        storage: SecureStorage,
        hardwareIdProvider: @Sendable @escaping () throws -> String,
        modelProvider: @Sendable @escaping () -> String,
        osVersionProvider: @Sendable @escaping () -> String
    ) {
        self.transport = transport
        self.attestor = attestor
        self.storage = storage
        bindingStore = AttestedDeviceStore(storage: storage)
        self.hardwareIdProvider = hardwareIdProvider
        self.modelProvider = modelProvider
        self.osVersionProvider = osVersionProvider
    }

    // MARK: DeviceAttestationService — the binding this device holds

    /// Whether this device is enrolled **for this entry point**. A handle issued
    /// under another one answers false: the device is not enrolled here, and
    /// sending that handle is what gets it refused and its record retired.
    /// The binding also has to name a key this device still holds. The sibling SDK
    /// compares the stored thumbprint against the key at the handle; App Attest
    /// hands back an opaque identifier and no way to read a key back, so the
    /// question is put to the key itself: it signs, or the platform says it is not
    /// a key this device has.
    ///
    /// A key can go for several reasons — the app was deleted and reinstalled, the
    /// device was restored, the platform invalidated it — and none of them leaves
    /// anything on the device to read. Asking covers all of them. Without it a
    /// binding that looks whole sends every request into a failure with nothing to
    /// recover from.
    /// Raises when the store could not be read, which is not the same answer as
    /// `false`: `false` runs the cold sequence, and running it against a paypoint
    /// that is already enrolled registers a second device for it.
    public func isAttested(for entry: String) async throws -> Bool {
        guard let binding = try binding(for: entry) else {
            return false
        }
        return await keyIsStillHeld(binding)
    }

    /// Whether the platform will still sign with this binding's key.
    ///
    /// Signs over a fixed hash that is sent nowhere: the answer is whether the
    /// call throws, not what it returns.
    ///
    /// Two codes mean the key cannot be used and the rest do not: see
    /// `deviceCheckUnusableKeyCodes`. Re-enrolling on any other answer would cost
    /// an enrolment for a key that was working.
    func keyIsStillHeld(_ binding: AttestedDevice) async -> Bool {
        do {
            _ = try await attestor.generateAssertion(
                AppAttestKeyId(binding.keyId),
                clientDataHash: Self.keyProbeHash
            )
            return true
        } catch {
            let nsError = error as NSError
            guard nsError.domain == Self.deviceCheckErrorDomain,
                  Self.deviceCheckUnusableKeyCodes.contains(nsError.code)
            else {
                logger.info("[attest] the key could not be checked; keeping the binding")
                return true
            }
            logger.info("[attest] the stored binding names a key this device no longer holds")
            clearCache(for: binding.entry)
            return false
        }
    }

    /// Constant, because nothing verifies this signature. A hash is required and
    /// its content is immaterial.
    static let keyProbeHash = ClientDataHash(Data(SHA256.hash(data: Data("payabli.keyProbe".utf8))))

    public func cachedDeviceId(for entry: String) throws -> String? {
        try binding(for: entry)?.deviceId
    }

    /// Drops this entry point's binding and leaves every other one alone: a
    /// refusal is about the paypoint that refused, and the other bindings still
    /// name keys that work.
    ///
    /// Every caller is already reporting a failure of its own and cannot carry a
    /// second one, so a store that refuses the drop is recorded and not raised. The
    /// binding is not left to be trusted: it names a key the platform has just
    /// refused, so the next warm check reads it, is refused again, and re-enrols,
    /// and the enrolment overwrites the entry.
    public func clearCache(for entry: String) {
        do {
            try bindingStore.forget(entry: entry)
            try bindingStore.forgetPendingKey(for: entry)
        } catch {
            logger.info("[attest] the binding for this paypoint could not be dropped")
        }
    }

    /// Runs a store operation and reports a failure as this SDK's own error.
    ///
    /// Everything crossing this protocol is a `PayabliTTPError`, because the domain
    /// and the code are what the ObjC, MAUI, Flutter and React Native bridges map.
    /// A `KeychainError` thrown as it arrived carries another domain, and every
    /// bridge reports it as a bare failure with nothing naming the cause.
    private func reportingStorageFailure<T>(_ work: () throws -> T) throws -> T {
        do {
            return try work()
        } catch let error as PayabliTTPError {
            throw error
        } catch {
            throw PayabliTTPError.attestationFailed(
                reason: "The stored device binding could not be read or written"
            )
        }
    }

    // MARK: - The key an attestation is part way through

    func pendingKey(for entry: String) throws -> String? {
        try reportingStorageFailure { try bindingStore.pendingKey(for: entry) }
    }

    func rememberPendingKey(_ keyId: String, for entry: String) throws {
        try reportingStorageFailure { try bindingStore.rememberPendingKey(keyId, for: entry) }
    }

    func allBindings() throws -> DeviceBindings {
        try reportingStorageFailure { try bindingStore.bindings() }
    }

    /// The binding held for an entry point, for tests and for the accessors above.
    func binding(for entry: String) throws -> AttestedDevice? {
        try reportingStorageFailure { try bindingStore.binding(for: entry) }
    }

    func remember(_ record: AttestedDevice) throws {
        try reportingStorageFailure { try bindingStore.remember(record) }
    }

    /// The value registration identifies this install by.
    ///
    /// Wrapped like every other store access: the default provider reads the
    /// Keychain and mints into it, so it fails the same way the binding reads do
    /// and has to reach a caller as the same error.
    func hardwareId() throws -> String {
        try reportingStorageFailure { try hardwareIdProvider() }
    }

    func forgetPendingKey(for entry: String) throws {
        try reportingStorageFailure { try bindingStore.forgetPendingKey(for: entry) }
    }
}

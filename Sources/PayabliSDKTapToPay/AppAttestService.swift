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

    // Injected so tests on macOS can substitute deterministic values. The hardware
    // identifier reads and may write the store, so it raises.
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

    /// Whether this device is enrolled for this entry point. A handle issued under
    /// another one answers false, and the binding also has to name a key this device
    /// still holds — a key can go on reinstall, restore or platform invalidation,
    /// and none of those leaves anything on the device to read.
    ///
    /// Raises when the store could not be read, which is not the same answer as
    /// `false`: `false` runs the cold sequence and registers a second device for a
    /// paypoint that is already enrolled.
    public func isAttested(for entry: String) async throws -> Bool {
        guard let binding = try binding(for: entry) else {
            return false
        }
        return await keyIsStillHeld(binding)
    }

    /// Whether the platform will still sign with this binding's key.
    ///
    /// Signs over a fixed hash that is sent nowhere: the answer is whether the call
    /// throws. Only `deviceCheckUnusableKeyCodes` mean the key cannot be used;
    /// re-enrolling on any other answer costs an enrolment for a working key.
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
            forgetIfUnchanged(binding)
            return false
        }
    }

    /// Drops the binding a refusal was about while it is still the one held, and
    /// raises if the store refuses. The pending key belongs to whatever is running
    /// now.
    @discardableResult
    func forgetRefused(_ binding: AttestedDevice) throws -> Bool {
        try reportingStorageFailure {
            try bindingStore.forget(entry: binding.entry, ifStill: binding)
        }
    }

    /// Drops the binding this probe asked about, and only that one.
    ///
    /// The probe suspends, so the entry point can hold a binding attested while the
    /// answer was travelling, and dropping by entry point would take that one for a
    /// key it never named. The pending key is left alone for the same reason.
    func forgetIfUnchanged(_ binding: AttestedDevice) {
        do {
            let dropped = try bindingStore.forget(entry: binding.entry, ifStill: binding)
            if !dropped {
                logger.info("[attest] this paypoint holds a newer binding; the probed one is already gone")
            }
        } catch {
            logger.info("[attest] the binding for this paypoint could not be dropped")
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
    /// Raises when the store refuses. A binding refused by the service names a key
    /// the platform still signs with, so a warm check finds it sound and sends the
    /// same refused binding again.
    ///
    /// A caller acting on a refused key uses `forgetIfUnchanged` instead: it holds
    /// the record its answer is about, and the entry point may hold a newer one.
    public func clearCache(for entry: String) throws {
        try reportingStorageFailure {
            try bindingStore.forgetEverything(for: entry)
        }
    }

    @discardableResult
    public func forgetRefusedBinding(entry: String, deviceId: String, keyId: String) throws -> Bool {
        try forgetRefused(AttestedDevice(entry: entry, deviceId: deviceId, keyId: keyId))
    }

    /// Runs a store operation and reports a failure as this SDK's own error.
    ///
    /// Everything crossing this protocol is a `PayabliTTPError`: the domain and the
    /// code are what the ObjC, MAUI, Flutter and React Native bridges map, and a
    /// `KeychainError` carries another domain they all report as a bare failure.
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
    /// Keychain and mints into it, so it fails the same way the binding reads do.
    func hardwareId() throws -> String {
        try reportingStorageFailure { try hardwareIdProvider() }
    }

    func forgetPendingKey(for entry: String) throws {
        try reportingStorageFailure { try bindingStore.forgetPendingKey(for: entry) }
    }
}

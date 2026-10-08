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
/// `entry` is supplied per call by the facade (`PayabliTTP`) to match the
/// `DeviceAttestationService` protocol, and is never cached on this service.
///
/// Companion files (same folder, PRD §7.2):
///   - `AppAttestService+Attest.swift`     — attestation + assertions
///   - `AppAttestService+Activation.swift` — `/activate` endpoint
///   - `AppAttestService+Requests.swift`   — shared envelope plumbing
///   - `AppAttestService+Defaults.swift`   — hardware-identifier providers
///   - `AppAttestWireFormat.swift`         — request/response DTOs
package final class AppAttestService: DeviceAttestationService, @unchecked Sendable {
    let transport: any PayabliTransport
    let attestor: AppAttestor
    let storage: SecureStorage
    let bindingStore: AttestedDeviceStore
    let logger = PayabliLogger(category: .taptopay)

    /// Injected so tests on macOS can substitute deterministic values. The hardware
    /// identifier reads and may write the store, so it raises.
    let hardwareIdProvider: @Sendable () throws -> String
    /// The App ID `/attest` is sent, `nil` when it cannot be read.
    let appIdProvider: @Sendable () throws -> String?
    let modelProvider: @Sendable () -> String
    let osVersionProvider: @Sendable () -> String

    /// The App ID is read from the access group of the install identifier's item, which
    /// `/register` has written before `/attest` needs it.
    package convenience init(
        transport: any PayabliTransport,
        attestor: AppAttestor,
        storage: KeychainStorage,
        deviceIdentity: DeviceIdentity
    ) {
        self.init(
            transport: transport,
            attestor: attestor,
            storage: storage,
            hardwareIdProvider: { try deviceIdentity.value() },
            appIdProvider: {
                AppIdentifier.derive(accessGroup: try storage.accessGroup(forKey: PayabliKeychainKey.installId))
            },
            modelProvider: AppAttestService.defaultModel,
            osVersionProvider: AppAttestService.defaultOSVersion
        )
    }

    init(
        transport: any PayabliTransport,
        attestor: AppAttestor,
        storage: SecureStorage,
        hardwareIdProvider: @Sendable @escaping () throws -> String,
        appIdProvider: @Sendable @escaping () throws -> String?,
        modelProvider: @Sendable @escaping () -> String,
        osVersionProvider: @Sendable @escaping () -> String
    ) {
        self.transport = transport
        self.attestor = attestor
        self.storage = storage
        bindingStore = AttestedDeviceStore(storage: storage)
        self.hardwareIdProvider = hardwareIdProvider
        self.appIdProvider = appIdProvider
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
    /// paypoint that is already enrolled. Raises too when the key check cannot answer.
    package func isAttested(for entry: String) async throws -> Bool {
        // The entry point's turn, so no attestation replaces the binding while its key is being checked.
        try await Self.attestations.takingTurns(entry) {
            guard let binding = try self.binding(for: entry) else {
                return false
            }
            return try await self.keyIsStillHeld(binding)
        }
    }

    /// Whether the platform will still sign with this binding's key.
    ///
    /// Signs over a fixed hash that is sent nowhere: the answer is whether the call
    /// throws. Only `deviceCheckUnusableKeyCodes` mean the key cannot be used, and
    /// drop the binding. A `deviceSetupError` raises as itself, and any other failure
    /// raises `deviceKeyUnavailable`; both keep the binding, because re-enrolling
    /// costs an enrolment for a key that may still work.
    func keyIsStillHeld(_ binding: AttestedDevice) async throws -> Bool {
        do {
            _ = try await attestor.generateAssertion(
                AppAttestKeyId(binding.keyId),
                clientDataHash: Self.keyProbeHash
            )
            return true
        } catch {
            if let setupError = Self.deviceSetupError(for: error) {
                logger.info("[attest] the key could not be checked; keeping the binding")
                throw setupError
            }
            let nsError = error as NSError
            let isDeviceCheck = nsError.domain == Self.deviceCheckErrorDomain
            guard isDeviceCheck, Self.deviceCheckUnusableKeyCodes.contains(nsError.code) else {
                logger.info("[attest] the key could not be checked; keeping the binding")
                throw TapToPayError(
                    type: .deviceKeyUnavailable,
                    reason: "The device key could not be checked",
                    detail: "\(nsError.domain) \(nsError.code)"
                )
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

    package func cachedDeviceId(for entry: String) throws -> String? {
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
    package func clearCache(for entry: String) throws {
        try reportingStorageFailure {
            try bindingStore.forgetEverything(for: entry)
        }
    }

    @discardableResult
    package func forgetRefusedBinding(entry: String, deviceId: String, keyId: String) throws -> Bool {
        try forgetRefused(AttestedDevice(entry: entry, deviceId: deviceId, keyId: keyId))
    }

    /// Runs a store operation and reports a failure as this SDK's own error.
    ///
    /// A `KeychainError` carries another domain the ObjC, MAUI, Flutter and React
    /// Native bridges all report as a bare failure. A Keychain status is storage that
    /// did not answer, which every read and write meets before the first unlock after
    /// a boot; anything else the store raises is this SDK's own.
    private func reportingStorageFailure<T>(_ work: () throws -> T) throws -> T {
        do {
            return try work()
        } catch let error as PayabliTTPError {
            throw error
        } catch let error as TapToPayError {
            throw error
        } catch let KeychainStorage.KeychainError.underlying(status) {
            throw TapToPayError(
                type: .deviceKeyUnavailable,
                reason: "The device's secure storage did not answer",
                detail: "OSStatus \(status)"
            )
        } catch {
            throw TapToPayError(
                type: .sdkInternalError,
                reason: "The stored device binding could not be read or written",
                detail: nil
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
    ///
    /// Raises rather than sending a blank one, which is what an app with no bundle
    /// identifier produces.
    func hardwareId() throws -> String {
        let hardwareId = try reportingStorageFailure { try hardwareIdProvider() }
        guard !hardwareId.isEmpty else {
            throw TapToPayError(
                type: .deviceIdentityUnavailable,
                reason: "The app's bundle identifier could not be read",
                detail: nil
            )
        }
        return hardwareId
    }

    /// The App ID `/attest` is sent. Raises rather than sending a blank one: with no
    /// Keychain access group to read it from, the app is not configured for App Attest.
    func appId() throws -> String {
        guard let appId = try reportingStorageFailure({ try appIdProvider() }) else {
            throw TapToPayError(
                type: .deviceSetupNotConfigured,
                reason: "The App ID could not be read from the Keychain",
                detail: nil
            )
        }
        return appId
    }

    func forgetPendingKey(for entry: String) throws {
        try reportingStorageFailure { try bindingStore.forgetPendingKey(for: entry) }
    }
}

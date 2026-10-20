import CryptoKit
import Foundation
import PayabliSDKCore
import Security

// MARK: - AppAttestService

/// Production `DeviceAttestationService` over `DCAppAttestService`. `attest` registers a new key and stores the
/// paypoint's binding in the Keychain; with a still-usable binding it is skipped and `generateAssertion()` signs.
/// `activateDevice` takes a partner-supplied out-of-band code; `entry` comes per call and is never cached.
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
    ///
    /// - Parameters:
    ///   - transport: what every attestation request is sent over.
    ///   - attestor: what signs and attests on this device.
    ///   - storage: the Keychain the bindings and the install identifier are held in.
    ///   - deviceIdentity: the install identifier `hardwareId()` sends.
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

    /// Whether this device is enrolled for this entry point, with a binding naming a key it still holds.
    ///
    /// Raises when the store cannot be read or the key check cannot answer: answering `false` there
    /// registers a second device for a paypoint already enrolled.
    ///
    /// - Parameter entry: the entry point whose held binding is asked about.
    /// - Returns: whether the entry point is enrolled, false with no binding held or one naming an unheld key.
    package func isAttested(for entry: String) async throws -> Bool {
        // The entry point's turn, so no attestation replaces the binding while its key is being checked.
        try await Self.attestations.takingTurns(entry) {
            guard let binding = try self.binding(for: entry) else {
                return false
            }
            return try await self.keyIsStillHeld(binding)
        }
    }

    /// Whether the platform will still sign with this binding's key, by signing a hash sent nowhere.
    /// Only `deviceCheckUnusableKeyCodes` drop the binding: re-enrolling costs an enrolment for a key
    /// that may still work, so every other failure keeps it and raises.
    ///
    /// - Parameter binding: the stored binding whose key the probe signs with.
    /// - Returns: whether the binding's key still signs on this device.
    func keyIsStillHeld(_ binding: AttestedDevice) async throws -> Bool {
        do {
            _ = try await attestor.generateAssertion(
                AppAttestKeyId(binding.keyId),
                clientDataHash: Self.keyProbeHash
            )
            return true
        } catch let error as TapToPayError {
            throw error
        } catch let error as CancellationError {
            throw error
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
    ///
    /// - Parameter binding: the binding the refusal named, dropped only while it is still the one held.
    /// - Returns: whether the binding was dropped.
    @discardableResult
    func forgetRefused(_ binding: AttestedDevice) throws -> Bool {
        try reportingStorageFailure {
            try bindingStore.forget(entry: binding.entry, ifStill: binding)
        }
    }

    /// Drops the binding this probe asked about, and only that one.
    ///
    /// The probe suspends, so the entry point can hold a binding attested meanwhile; a newer one
    /// never drops for the key this probe asked about.
    ///
    /// - Parameter binding: the binding the probe asked about, dropped only while it is still the one held.
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

    /// Drops this entry point's binding and leaves every other one alone.
    ///
    /// Raises when the store refuses. A binding refused by the service still signs, so a warm check
    /// sends the same one again; a caller acting on a refused key uses `forgetIfUnchanged`.
    ///
    /// - Parameter entry: the entry point whose binding is dropped.
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
    /// A `KeychainError`'s status is reported by what repairs it: a missing entitlement is the
    /// app's, an invalid parameter is this SDK's, anything else is storage that did not answer.
    ///
    /// - Parameter work: the store operation, run once.
    /// - Returns: what `work` answered.
    private func reportingStorageFailure<T>(_ work: () throws -> T) throws -> T {
        do {
            return try work()
        } catch let error as PayabliTTPError {
            throw error
        } catch let error as TapToPayError {
            throw error
        } catch let KeychainStorage.KeychainError.underlying(status) {
            throw Self.storageError(status: status)
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
    ///
    /// - Parameter entry: the entry point whose held binding is asked for.
    /// - Returns: the entry point's binding, or `nil` where none is held.
    func binding(for entry: String) throws -> AttestedDevice? {
        try reportingStorageFailure { try bindingStore.binding(for: entry) }
    }

    func remember(_ record: AttestedDevice) throws {
        try reportingStorageFailure { try bindingStore.remember(record) }
    }

    private static func storageError(status: OSStatus) -> TapToPayError {
        switch status {
        case errSecMissingEntitlement:
            TapToPayError(
                type: .deviceSetupNotConfigured,
                reason: "The app lacks the entitlement its Keychain items need",
                detail: "OSStatus \(status)"
            )
        case errSecParam:
            TapToPayError(
                type: .sdkInternalError,
                reason: "The SDK asked the Keychain with an invalid parameter",
                detail: "OSStatus \(status)"
            )
        default:
            TapToPayError(
                type: .deviceKeyUnavailable,
                reason: "The device's secure storage did not answer",
                detail: "OSStatus \(status)"
            )
        }
    }

    /// The value registration identifies this install by. Raises rather than sending a blank one,
    /// which is what an app with no bundle identifier produces.
    ///
    /// - Returns: the install identifier `/register` sends, never blank.
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
    ///
    /// - Returns: the App ID `/attest` sends, never blank.
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

import Foundation
import PayabliSDKCore

// MARK: - AppAttestService

/// Production `DeviceAttestationService` (PRD §18).
///
/// Bridges Apple's `DCAppAttestService` with the Payabli backend so a TTP
/// session can prove it runs on a genuine, unmodified iOS app:
///
/// - First-run flow (`attest`): challenge → register → generate key →
///   attest key → post attestation. Persists `keyId` + `deviceId` in the
///   Keychain (PRD §22.1).
/// - Warm path: when both identifiers are already cached, `attest` is
///   skipped and per-request assertions are produced by
///   `generateAssertion()` (PRD §18.2).
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
    let installStorage: InstallScopedStorage
    let bindingStore: AttestedDeviceStore
    let logger = PayabliLogger(category: .taptopay)

    // Injected so tests on macOS can substitute deterministic values.
    let hardwareIdProvider: @Sendable () -> String
    let deviceNameProvider: @Sendable () -> String
    let modelProvider: @Sendable () -> String
    let osVersionProvider: @Sendable () -> String

    public convenience init(
        transport: any PayabliTransport,
        attestor: AppAttestor,
        storage: SecureStorage,
        installStorage: InstallScopedStorage = UserDefaultsInstallStorage()
    ) {
        self.init(
            transport: transport,
            attestor: attestor,
            storage: storage,
            installStorage: installStorage,
            hardwareIdProvider: AppAttestService.defaultHardwareId,
            deviceNameProvider: AppAttestService.defaultDeviceName,
            modelProvider: AppAttestService.defaultModel,
            osVersionProvider: AppAttestService.defaultOSVersion
        )
    }

    init(
        transport: any PayabliTransport,
        attestor: AppAttestor,
        storage: SecureStorage,
        installStorage: InstallScopedStorage = UserDefaultsInstallStorage(),
        hardwareIdProvider: @Sendable @escaping () -> String,
        deviceNameProvider: @Sendable @escaping () -> String,
        modelProvider: @Sendable @escaping () -> String,
        osVersionProvider: @Sendable @escaping () -> String
    ) {
        self.transport = transport
        self.attestor = attestor
        self.storage = storage
        self.installStorage = installStorage
        bindingStore = AttestedDeviceStore(storage: storage)
        self.hardwareIdProvider = hardwareIdProvider
        self.deviceNameProvider = deviceNameProvider
        self.modelProvider = modelProvider
        self.osVersionProvider = osVersionProvider
    }

    // MARK: DeviceAttestationService — the binding this device holds

    /// Whether this device is enrolled **for this entry point**. A handle issued
    /// under another one answers false: the device is not enrolled here, and
    /// sending that handle is what gets it refused and its record retired.
    /// The binding also has to belong to this installation. The Keychain outlives
    /// app deletion and the Secure Enclave key it names does not, so a reinstall
    /// finds a complete-looking binding whose key Apple will never sign with
    /// again. Answering true there sends every request into a failure with nothing
    /// to recover from.
    public func isAttested(for entry: String) -> Bool {
        isCurrentInstall && bindingStore.load().binding(for: entry) != nil
    }

    public func cachedDeviceId(for entry: String) -> String? {
        bindingStore.load().binding(for: entry)?.deviceId
    }

    /// Drops this entry point's binding and leaves every other one alone. A
    /// refusal is about the paypoint that refused; discarding the rest would
    /// re-enrol devices nothing was wrong with.
    public func clearCache(for entry: String) {
        bindingStore.save(bindingStore.load().without(entry: entry))
        storage.remove(forKey: PayabliKeychainKey.pendingKeyId)
    }

    /// The binding held for an entry point, for tests and for the two accessors
    /// above.
    func binding(for entry: String) -> AttestedDevice? {
        bindingStore.load().binding(for: entry)
    }

    // MARK: - Which installation wrote this

    /// Whether the stored bindings were written by the installation running now.
    /// The two halves are written together and disagree only after a reinstall.
    var isCurrentInstall: Bool {
        guard let container = installStorage.string(forKey: PayabliInstallKey.installId) else {
            return false
        }
        return container == storage.string(forKey: PayabliKeychainKey.installId)
    }

    /// Discards bindings a previous installation left behind, then stamps this
    /// one. Called at the top of `attest()`, the only path that mints a key, so
    /// within one installation the stamp matches and a retry keeps its pending
    /// key.
    func beginInstallGeneration() {
        if !isCurrentInstall {
            let stale = !bindingStore.load().bindings.isEmpty
                || storage.string(forKey: PayabliKeychainKey.pendingKeyId) != nil
            if stale {
                logger.info("[attest] bindings predate this install — discarding them and attesting cold")
                storage.remove(forKey: PayabliKeychainKey.deviceBindings)
                storage.remove(forKey: PayabliKeychainKey.pendingKeyId)
            }
            let stamp = UUID().uuidString
            try? storage.set(stamp, forKey: PayabliKeychainKey.installId)
            installStorage.set(stamp, forKey: PayabliInstallKey.installId)
        }
    }

    func remember(_ record: AttestedDevice) {
        bindingStore.save(bindingStore.load().with(record))
    }
}

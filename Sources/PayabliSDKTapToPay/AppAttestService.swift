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
        storage: SecureStorage
    ) {
        self.init(
            transport: transport,
            attestor: attestor,
            storage: storage,
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
        hardwareIdProvider: @Sendable @escaping () -> String,
        deviceNameProvider: @Sendable @escaping () -> String,
        modelProvider: @Sendable @escaping () -> String,
        osVersionProvider: @Sendable @escaping () -> String
    ) {
        self.transport = transport
        self.attestor = attestor
        self.storage = storage
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
    public func isAttested(for entry: String) async -> Bool {
        guard let binding = bindingStore.binding(for: entry) else {
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
    private func keyIsStillHeld(_ binding: AttestedDevice) async -> Bool {
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

    public func cachedDeviceId(for entry: String) -> String? {
        bindingStore.binding(for: entry)?.deviceId
    }

    /// Drops this entry point's binding and leaves every other one alone: a
    /// refusal is about the paypoint that refused, and the other bindings still
    /// name keys that work.
    public func clearCache(for entry: String) {
        bindingStore.forget(entry: entry)
        storage.remove(forKey: PayabliKeychainKey.pendingKeyId)
    }

    /// The binding held for an entry point, for tests and for the two accessors
    /// above.
    // MARK: - The key an attestation is part way through

    /// Which entry point minted the pending key, and the key. Held as one item so
    /// the two cannot disagree.
    struct PendingKey: Codable {
        let entry: String
        let keyId: String
    }

    func pendingKey() -> PendingKey? {
        guard let raw = storage.string(forKey: PayabliKeychainKey.pendingKeyId),
              let data = raw.data(using: .utf8)
        else {
            return nil
        }
        return try? JSONDecoder().decode(PendingKey.self, from: data)
    }

    func rememberPendingKey(_ keyId: String, for entry: String) throws {
        let pending = PendingKey(entry: entry, keyId: keyId)
        guard let data = try? JSONEncoder().encode(pending),
              let raw = String(bytes: data, encoding: .utf8)
        else {
            throw PayabliTTPError.attestationFailed(reason: "The pending key could not be encoded")
        }
        try storage.set(raw, forKey: PayabliKeychainKey.pendingKeyId)
    }

    func allBindings() -> DeviceBindings {
        bindingStore.bindings()
    }

    func binding(for entry: String) -> AttestedDevice? {
        bindingStore.binding(for: entry)
    }

    func remember(_ record: AttestedDevice) throws {
        try bindingStore.remember(record)
    }
}

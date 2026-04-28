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

    let service: PayabliService
    let auth: PayabliAuth
    let attestor: AppAttestor
    let storage: SecureStorage
    let logger = PayabliLogger(category: .taptopay)

    // Injected so tests on macOS can substitute deterministic values.
    let hardwareIdProvider: @Sendable () -> String
    let deviceNameProvider: @Sendable () -> String
    let modelProvider: @Sendable () -> String
    let osVersionProvider: @Sendable () -> String

    public init(
        service: PayabliService,
        auth: PayabliAuth,
        attestor: AppAttestor,
        storage: SecureStorage,
        hardwareIdProvider: @Sendable @escaping () -> String = AppAttestService.defaultHardwareId,
        deviceNameProvider: @Sendable @escaping () -> String = AppAttestService.defaultDeviceName,
        modelProvider: @Sendable @escaping () -> String = AppAttestService.defaultModel,
        osVersionProvider: @Sendable @escaping () -> String = AppAttestService.defaultOSVersion
    ) {
        self.service = service
        self.auth = auth
        self.attestor = attestor
        self.storage = storage
        self.hardwareIdProvider = hardwareIdProvider
        self.deviceNameProvider = deviceNameProvider
        self.modelProvider = modelProvider
        self.osVersionProvider = osVersionProvider
    }

    // MARK: DeviceAttestationService — cached state

    public var isAlreadyAttested: Bool {
        storage.string(forKey: PayabliKeychainKey.keyId) != nil
            && storage.string(forKey: PayabliKeychainKey.deviceId) != nil
    }

    public var cachedDeviceId: String? {
        storage.string(forKey: PayabliKeychainKey.deviceId)
    }

    public func clearCache() {
        storage.remove(forKey: PayabliKeychainKey.keyId)
        storage.remove(forKey: PayabliKeychainKey.deviceId)
    }
}

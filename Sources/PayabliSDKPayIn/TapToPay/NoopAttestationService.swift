import Foundation

/// No-op `DeviceAttestationService` used only when `DeviceCheck` is unavailable
/// at build time (e.g. macOS test host). All operations throw
/// `.attestationFailed` so callers fail loudly rather than silently proceeding
/// with bogus state.
public final class NoopAttestationService: DeviceAttestationService, @unchecked Sendable {

    public init() {}

    public var isAlreadyAttested: Bool { false }

    public var cachedDeviceId: String? { nil }

    public func attest(entry: String, appId: String) async throws -> AttestationResult {
        throw PayabliTTPError.attestationFailed(reason: "App Attest unavailable on this platform")
    }

    public func generateAssertion(for data: Data) async throws -> AssertionHeaders {
        throw PayabliTTPError.attestationFailed(reason: "App Attest unavailable on this platform")
    }

    public func requestActivationCode(entry: String) async throws -> ActivationCodeInfo {
        throw PayabliTTPError.activationFailed(reason: "App Attest unavailable on this platform")
    }

    public func activateDevice(activationCode: String, entry: String) async throws {
        throw PayabliTTPError.activationFailed(reason: "App Attest unavailable on this platform")
    }

    public func clearCache() {}
}

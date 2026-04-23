import Foundation

#if canImport(DeviceCheck)
import DeviceCheck
#endif

/// Abstraction over Apple's `DCAppAttestService` so the rest of the SDK can
/// be unit-tested without an iOS device.
///
/// Production uses `RealAppAttestor`; tests use `MockAppAttestor` (in the
/// test target).
public protocol AppAttestor: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> String
    func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data
    func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data
}

#if canImport(DeviceCheck)
/// Production `AppAttestor` backed by `DCAppAttestService`.
@available(iOS 14.0, macOS 11.3, *)
public final class RealAppAttestor: AppAttestor, @unchecked Sendable {
    public init() {}

    public var isSupported: Bool {
        DCAppAttestService.shared.isSupported
    }

    public func generateKey() async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            DCAppAttestService.shared.generateKey { keyId, error in
                if let error { continuation.resume(throwing: error); return }
                guard let keyId else {
                    continuation.resume(throwing: PayabliTTPError.attestationFailed(
                        reason: "generateKey returned nil"
                    ))
                    return
                }
                continuation.resume(returning: keyId)
            }
        }
    }

    public func attestKey(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DCAppAttestService.shared.attestKey(keyId, clientDataHash: clientDataHash) { attestation, error in
                if let error { continuation.resume(throwing: error); return }
                guard let attestation else {
                    continuation.resume(throwing: PayabliTTPError.attestationFailed(
                        reason: "attestKey returned nil"
                    ))
                    return
                }
                continuation.resume(returning: attestation)
            }
        }
    }

    public func generateAssertion(_ keyId: String, clientDataHash: Data) async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            DCAppAttestService.shared.generateAssertion(keyId, clientDataHash: clientDataHash) { assertion, error in
                if let error { continuation.resume(throwing: error); return }
                guard let assertion else {
                    continuation.resume(throwing: PayabliTTPError.attestationFailed(
                        reason: "generateAssertion returned nil"
                    ))
                    return
                }
                continuation.resume(returning: assertion)
            }
        }
    }
}
#endif

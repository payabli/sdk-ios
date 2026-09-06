import Foundation

#if canImport(DeviceCheck)
    import DeviceCheck
#endif

// MARK: - Domain types

/// Apple App Attest key identifier returned by `DCAppAttestService.generateKey`.
/// Wire-format: plain JSON string.
package struct AppAttestKeyId: Hashable, Sendable, Codable, CustomStringConvertible {
    package let rawValue: String

    package init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    package init(from decoder: Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    package var description: String {
        rawValue
    }
}

/// SHA-256 hash fed into `attestKey` / `generateAssertion` — 32 bytes.
package struct ClientDataHash: Hashable, Sendable {
    package let rawValue: Data
    package init(_ rawValue: Data) {
        self.rawValue = rawValue
    }
}

/// CBOR attestation blob returned by `attestKey`. Wire-format: base64 string.
package struct AttestationObject: Hashable, Sendable, Codable {
    package let rawValue: Data

    package init(_ rawValue: Data) {
        self.rawValue = rawValue
    }

    package init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let base64 = try container.decode(String.self)
        guard let data = Data(base64Encoded: base64) else {
            throw DecodingError.dataCorruptedError(
                in: container,
                debugDescription: "Invalid base64 AttestationObject"
            )
        }
        self.rawValue = data
    }

    package func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue.base64EncodedString())
    }

    package var base64: String {
        rawValue.base64EncodedString()
    }
}

/// CBOR assertion blob returned by `generateAssertion`. Emitted as base64
/// in the `X-App-Assertion` header.
package struct AppAttestAssertion: Hashable, Sendable {
    package let rawValue: Data
    package init(_ rawValue: Data) {
        self.rawValue = rawValue
    }

    package var base64: String {
        rawValue.base64EncodedString()
    }
}

// MARK: - Protocol

/// Abstraction over Apple's `DCAppAttestService` so the rest of the SDK can
/// be unit-tested without an iOS device.
///
/// Production uses `RealAppAttestor`; tests use `MockAppAttestor` (in the
/// test target).
package protocol AppAttestor: Sendable {
    var isSupported: Bool { get }
    func generateKey() async throws -> AppAttestKeyId
    func attestKey(_ keyId: AppAttestKeyId, clientDataHash: ClientDataHash) async throws -> AttestationObject
    func generateAssertion(_ keyId: AppAttestKeyId, clientDataHash: ClientDataHash) async throws -> AppAttestAssertion
}

// MARK: - Production impl

#if canImport(DeviceCheck)
    /// Production `AppAttestor` backed by `DCAppAttestService`.
    ///
    /// `DCAppAttestService` itself is iOS 14+ / macOS 11.3+, which is well below
    /// this package's declared minimums (iOS 16.7 / macOS 12), so no extra
    /// `@available` gate is required.
    package final class RealAppAttestor: AppAttestor, @unchecked Sendable {
        package init() {}

        package var isSupported: Bool {
            DCAppAttestService.shared.isSupported
        }

        package func generateKey() async throws -> AppAttestKeyId {
            try await withCheckedThrowingContinuation { continuation in
                DCAppAttestService.shared.generateKey { keyId, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let keyId else {
                        continuation.resume(throwing: PayabliTTPError.attestationFailed(
                            reason: "generateKey returned nil"
                        ))
                        return
                    }
                    continuation.resume(returning: AppAttestKeyId(keyId))
                }
            }
        }

        package func attestKey(_ keyId: AppAttestKeyId, clientDataHash: ClientDataHash) async throws -> AttestationObject {
            try await withCheckedThrowingContinuation { continuation in
                DCAppAttestService.shared.attestKey(keyId.rawValue, clientDataHash: clientDataHash.rawValue) { attestation, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let attestation else {
                        continuation.resume(throwing: PayabliTTPError.attestationFailed(
                            reason: "attestKey returned nil"
                        ))
                        return
                    }
                    continuation.resume(returning: AttestationObject(attestation))
                }
            }
        }

        package func generateAssertion(_ keyId: AppAttestKeyId, clientDataHash: ClientDataHash) async throws -> AppAttestAssertion {
            try await withCheckedThrowingContinuation { continuation in
                DCAppAttestService.shared.generateAssertion(keyId.rawValue, clientDataHash: clientDataHash.rawValue) { assertion, error in
                    if let error {
                        continuation.resume(throwing: error)
                        return
                    }
                    guard let assertion else {
                        continuation.resume(throwing: PayabliTTPError.attestationFailed(
                            reason: "generateAssertion returned nil"
                        ))
                        return
                    }
                    continuation.resume(returning: AppAttestAssertion(assertion))
                }
            }
        }
    }
#endif

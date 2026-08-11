import Foundation

#if canImport(DeviceCheck)
    import DeviceCheck
#endif

// MARK: - Domain types

/// Apple App Attest key identifier returned by `DCAppAttestService.generateKey`.
/// Wire-format: plain JSON string.
public struct AppAttestKeyId: Hashable, Sendable, Codable, CustomStringConvertible {
    public let rawValue: String

    public init(_ rawValue: String) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
        self.rawValue = try decoder.singleValueContainer().decode(String.self)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }

    public var description: String {
        rawValue
    }
}

/// SHA-256 hash fed into `attestKey` / `generateAssertion` — 32 bytes.
public struct ClientDataHash: Hashable, Sendable {
    public let rawValue: Data
    public init(_ rawValue: Data) {
        self.rawValue = rawValue
    }
}

/// CBOR attestation blob returned by `attestKey`. Wire-format: base64 string.
public struct AttestationObject: Hashable, Sendable, Codable {
    public let rawValue: Data

    public init(_ rawValue: Data) {
        self.rawValue = rawValue
    }

    public init(from decoder: Decoder) throws {
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

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue.base64EncodedString())
    }

    public var base64: String {
        rawValue.base64EncodedString()
    }
}

/// CBOR assertion blob returned by `generateAssertion`. Emitted as base64
/// in the `X-App-Assertion` header.
public struct AppAttestAssertion: Hashable, Sendable {
    public let rawValue: Data
    public init(_ rawValue: Data) {
        self.rawValue = rawValue
    }

    public var base64: String {
        rawValue.base64EncodedString()
    }
}

// MARK: - Protocol

/// Abstraction over Apple's `DCAppAttestService` so the rest of the SDK can
/// be unit-tested without an iOS device.
///
/// Production uses `RealAppAttestor`; tests use `MockAppAttestor` (in the
/// test target).
public protocol AppAttestor: Sendable {
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
    public final class RealAppAttestor: AppAttestor, @unchecked Sendable {
        public init() {}

        public var isSupported: Bool {
            DCAppAttestService.shared.isSupported
        }

        public func generateKey() async throws -> AppAttestKeyId {
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

        public func attestKey(_ keyId: AppAttestKeyId, clientDataHash: ClientDataHash) async throws -> AttestationObject {
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

        public func generateAssertion(_ keyId: AppAttestKeyId, clientDataHash: ClientDataHash) async throws -> AppAttestAssertion {
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
